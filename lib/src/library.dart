// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_periphery/src/cpu_architecture.dart';

import 'native/lib_base64.dart';

const pkgName = 'dart_periphery';

final String sharedLib = 'libperiphery.so';

late DynamicLibrary _peripheryLib;
bool _isPeripheryLibLoaded = false;
String _peripheryLibPath = '';
String _tmpDirectory = Directory.systemTemp.path;
String _libraryFileName = '';
bool _reuseTmpFileLibrary = false;
bool _useFlutterPiAssetDir = false;

class PlatformException implements Exception {
  final String error;
  PlatformException(this.error);
  @override
  String toString() => error;
}

// Fix typo
// https://github.com/pezi/dart_periphery/pull/20
//@Deprecated("Fix typo in method name")
//void useSharedLibray() {
//  _peripheryLibPath = sharedLib;
//}

/// dart_periphery loads the shared library.
/// See [native-libraries](https://pub.dev/packages/dart_periphery#native-libraries) for details.
void useSharedLibrary() {
  _peripheryLibPath = sharedLib;
}

/// dart_periphery loads a custom library.
/// See [native-libraries](https://pub.dev/packages/dart_periphery#native-libraries) for details.
void setCustomLibrary(String absolutePath) {
  _peripheryLibPath = absolutePath;
}

/// Bypasses the autodetection of the CPU architecture.
void setCPUarchitecture(CpuArchitecture arch) {
  if (arch == CpuArchitecture.notSupported ||
      arch == CpuArchitecture.undefined) {
    throw LibraryException(
        LibraryErrorCode.invalidParameter, "Invalid parameter");
  }
  var cpu = arch.toString();
  cpu = cpu.substring(cpu.indexOf(".") + 1).toLowerCase();
  _libraryFileName = 'libperiphery_$cpu.so';
}

/// Sets the tmp directory for the extraction of the libperiphery.so file.
void setTempDirectory(String tmpDir) {
  _tmpDirectory = tmpDir;
}

/// Allows to load an existing libperiphery.so file from tmp directory.
void reuseTmpFileLibrary(bool reuse) {
  _reuseTmpFileLibrary = reuse;
}

/// Loads the library form the flutter-pi asset directory.
void loadLibFromFlutterAssetDir(bool use) {
  _useFlutterPiAssetDir = use;
}


String _autoDetectCPUarch() {
  CpuArch arch = CpuArch();
  if (arch.cpuArch == CpuArchitecture.notSupported) {
    throw LibraryException(LibraryErrorCode.cpuArchDetectionFailed,
        "Unable to detect CPU architecture, found '${arch.machine}' . Use 'setCustomLibrary(String absolutePath)' - see documentation https://github.com/pezi/dart_periphery, or create an issue https://github.com/pezi/dart_periphery/issues");
  }
  var cpu = arch.cpuArch.toString();
  cpu = cpu.substring(cpu.indexOf(".") + 1).toLowerCase();
  return 'libperiphery_$cpu.so';
}

/// dart_periphery loads the library from the actual directory.
/// See [native-libraries](https://pub.dev/packages/dart_periphery#native-libraries) for details.
void useLocalLibrary() {
  if (arch == CpuArchitecture.undefined) {
    _peripheryLibPath = './${_autoDetectCPUarch()}';
  } else {
    if (arch == CpuArchitecture.notSupported) {
      throw LibraryException(
          LibraryErrorCode.invalidParameter, "Invalid parameter");
    }
    var cpu = arch.toString();
    cpu = cpu.substring(cpu.indexOf(".") + 1).toLowerCase();
    _peripheryLibPath = './libperiphery_$cpu.so';
  }
}

enum LibraryErrorCode {
  libraryNotFound,
  cpuArchDetectionFailed,
  invalidParameter,
  invalidTmpDirectory,
  errorWritingLib
}

/// Library exception
class LibraryException implements Exception {
  final String errorMsg;
  final LibraryErrorCode errorCode;
  LibraryException(this.errorCode, this.errorMsg);
  @override
  String toString() => errorMsg;
}

// ignore: camel_case_types
typedef _getpId = Int32 Function();
typedef _GetpId = int Function();

bool _isFlutterPi = Platform.resolvedExecutable.endsWith('flutter-pi');

/// Returns true for a flutter-pi environment.
bool isFlutterPiEnv() {
  return _isFlutterPi;
}

var _flutterPiArgs = <String>[];

/// Returns the PID of the running program for linux, -1 for all other platforms.
int getPID() {
  if (!Platform.isLinux) {
    return -1;
  }
  final dylib = DynamicLibrary.open('libc.so.6');
  var getPid =
      dylib.lookup<NativeFunction<_getpId>>('getpid').asFunction<_GetpId>();
  return getPid();
}

/// Returns the argument list of the running flutter-pi program by
/// reading the /proc/PID/cmdline data. For a non flutter-pi environment
/// an empty list will be returned.
List<String> getFlutterPiArgs() {
  if (!isFlutterPiEnv()) {
    return const <String>[];
  }
  if (_flutterPiArgs.isEmpty) {
    var cmd = File('/proc/${getPID()}/cmdline').readAsBytesSync();
    var index = 0;
    for (var i = 0; i < cmd.length; ++i) {
      if (cmd[i] == 0) {
        _flutterPiArgs
            .add(String.fromCharCodes(Uint8List.sublistView(cmd, index, i)));
        index = i + 1;
      }
    }
  }
  return List.unmodifiable(_flutterPiArgs);
}

void saveLibrary(File file, String base64EncodedLib) {
  try {
    file.createSync(recursive: false);
    final decodedBytes = base64Decode(base64EncodedLib);
    // hint: a crash occures, if an used lib is written again
    file.writeAsBytesSync(decodedBytes);
  } on Error catch (e) {
    throw LibraryException(LibraryErrorCode.errorWritingLib, e.toString());
  } on Exception catch (e) {
    throw LibraryException(LibraryErrorCode.errorWritingLib, e.toString());
  }
}

/// Loads the Linux/CPU specific periphery library as a DynamicLibrary.
DynamicLibrary loadPeripheryLib() {
  if (_isPeripheryLibLoaded) {
    return _peripheryLib;
  }

  if (!Platform.isLinux) {
    throw PlatformException('dart_periphery is only supported for Linux!');
  }

  if (_peripheryLibPath.isEmpty) {
    if (isFlutterPiEnv() && _useFlutterPiAssetDir) {
      // load the library from the asset directory
      var args = getFlutterPiArgs();
      var index = 1;
      for (var i = 1; i < args.length; ++i) {
        // skip --release
        if (args[i].startsWith('--release')) {
          ++index;
          // skip options like -r, --rotation <degrees>
        } else if (args[i].startsWith('-')) {
          index += 2;
        } else {
          break;
        }
      }
      var assetDir = args[index];
      var separator = '';
      if (!assetDir.startsWith('/')) {
        separator = '/';
      }
      var dir = Directory.current.path + separator + assetDir;
      if (!dir.endsWith('/')) {
        dir += '/';
      }
      if (_libraryFileName.isEmpty) {
        _libraryFileName = _autoDetectCPUarch();
      }
      _peripheryLibPath = dir + _libraryFileName;
    } else {
      // store the appropriate in the system temp directory

      String base64EncodedLib = '';

      switch (Abi.current()) {
        case Abi.linuxArm:
          base64EncodedLib = arm;
          break;
        case Abi.linuxArm64:
          base64EncodedLib = arm64;
          break;
        case Abi.linuxIA32:
          base64EncodedLib = x86;
          break;
        case Abi.linuxX64:
          base64EncodedLib = x86_64;
          break;
        // case Abi.linuxRiscv64:

        default:
          throw LibraryException(LibraryErrorCode.invalidParameter,
              "Not supported CPU architecture");
      }

      if (_libraryFileName.isEmpty) {
        _libraryFileName = _autoDetectCPUarch();
      }

      if (_tmpDirectory.isEmpty) {
        throw LibraryException(
            LibraryErrorCode.invalidTmpDirectory, "Temp directory is empty");
      }
      if (!Directory(_tmpDirectory).existsSync()) {
        throw LibraryException(LibraryErrorCode.invalidTmpDirectory,
            "Temp directory does not exist");
      }

      if (_reuseTmpFileLibrary) {
        String path = _tmpDirectory + Platform.pathSeparator + _libraryFileName;
        final file = File(path);
        if (!file.existsSync()) {
          saveLibrary(file, base64EncodedLib);
        }
        _peripheryLibPath = path;
      } else {
        // fix https://github.com/pezi/flutter-pi-sensor-tester/issues/1
        String path =
            '$_tmpDirectory${Platform.pathSeparator}pid_${getPID()}_$_libraryFileName';
        final file = File(path);
        // avoid crash writing this file again from an other isolate
        if (!file.existsSync()) {
          saveLibrary(file, base64EncodedLib);
        }
        _peripheryLibPath = path;
      }
    }
  }

  _peripheryLib = DynamicLibrary.open(_peripheryLibPath);

  _isPeripheryLibLoaded = true;
  return _peripheryLib;
}

/// Returns the path of the periphery library. Empty string. if the
/// library is not loaded.
String getPeripheryLibPath() {
  return _peripheryLibPath;
}
