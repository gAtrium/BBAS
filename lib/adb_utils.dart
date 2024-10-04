import 'dart:convert';
import 'dart:core';
import 'dart:ffi';
import 'dart:io';
import 'package:betterbetteradbsync/w32_adb_executor.dart';
import 'package:charset/charset.dart';
import 'traverser.dart';

class AdbUtils {
  static String _adbPath = '';
  static String _chosenDevice = '';
  static List<String> _devices = [];
  static String get ChosenDevice => _chosenDevice;
  static List<String> get Devices => _devices;

  static void initialize() {
    _adbPath = _getAdbPathFromSystem();
  }

  static void setChosenDevice(String device) {
    _chosenDevice = device;
  }

  static String _getAdbPathFromSystem() {
    String adbPath = '';
    if (Platform.isWindows) {
      Process.runSync("where", ['adb']).stdout.split('\n').forEach((element) {
        if (element.contains('adb.exe') && adbPath.isEmpty) {
          adbPath = element;
        }
      });
    } else if (Platform.isLinux || Platform.isMacOS) {
      Process.runSync("which", ['adb']).stdout.split('\n').forEach((element) {
        if (element.contains('adb')) {
          adbPath = element;
        }
      });
    }
    _adbPath = adbPath;
    return adbPath;
  }

  static Future<List<String>> queryDevices() async {
    List<String> devices = [];
    ProcessResult result =
        await Process.run(_adbPath, ['devices'], runInShell: true);
    if (result.exitCode != 0) {
      print("Error while querying devices: ${result.stderr}");
      return devices;
    }
    List<String> lines = result.stdout.split('\n');
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty || lines[i].startsWith('List of devices')) {
        continue;
      }
      List<String> parts = lines[i].split('\t');
      devices.add(parts[0]);
    }
    _devices = devices;
    return devices;
  }

  static String _fix_pull_filename(String filename) {
    return filename
        .replaceAll(" ", "\\ ")
        .replaceAll("(", "\\(")
        .replaceAll(")", "\\)");
  }

  static Future<List<String>> queryDeviceNames() async {
    List<String> deviceNames = [];
    for (String device in _devices) {
      ProcessResult result = await Process.run(
          _adbPath, ['-s', device, 'shell', 'getprop', 'ro.product.model'],
          runInShell: true);
      if (result.exitCode != 0) {
        print("Error while querying device name: ${result.stderr}");
        deviceNames.add(device);
      } else {
        deviceNames.add("$device (${result.stdout.trim()})");
      }
    }
    return deviceNames;
  }

  static Future<bool> remoteFolderExists(String path) async {
    ProcessResult result = await Process.run(
        _adbPath, ['-s', _chosenDevice, 'shell', 'ls', path],
        runInShell: true);
    return result.exitCode == 0;
  }

  static Future<Traverser?> Traverse_Remote(String path) async {
    return _traverseDirectory(path);
  }

  static Future<List<String>> treeRemoteFiles(String path) async {
    List<String> files = [];
    RegExp lsSplitter = RegExp(
        r'([dwrx-]{10})\s{1,}\d+\s+\w+\s+\w+\s+(\d+)\s[\d-]+\s[\d:]+\s(.+)\n*');
    AdbCommandExecutor adbExecutor = AdbCommandExecutor();
    final result = await adbExecutor.executeAdbCommand('shell ls -la "$path"');

    List<String> lines = result.stdout.split('\n');
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].isEmpty) {
        continue;
      }
      RegExpMatch? parts = lsSplitter.firstMatch(lines[i]);
      if (parts == null) {
        print("Error while splitting ls output: ${lines[i]}");
        continue;
      }
      bool is_directory = parts.group(1)!.contains('d');
      String filename = parts.group(3)!;
      num size = num.parse(parts.group(2)!);
      if (filename.endsWith('.')) {
        continue;
      }
      if (is_directory) {
        print("Traversing child: $path$filename/");
        List<String> child =
            await treeRemoteFiles('$path${_fix_pull_filename(filename)}/');
        if (child.isNotEmpty) {
          files.addAll(child);
        }
      } else {
        //print("adding file $path$filename");
        files.add("$path/$filename");
      }
    }
    return files;
  }

  static Future<Traverser?> _traverseDirectory(String path) async {
    RegExp lsSplitter = RegExp(
        r'([dwrx-]{10})\s{1,}\d+\s+\w+\s+\w+\s+(\d+)\s[\d-]+\s[\d:]+\s(.+)\n*');
    AdbCommandExecutor adbExecutor = AdbCommandExecutor();
    final result = await adbExecutor.executeAdbCommand('shell ls -la "$path"');

    //ProcessResult result = await Process.run(_adbPath, ['-s', _chosenDevice, 'shell', 'ls', "-la" , path], runInShell: true);
    //if (result.exitCode != 0) {
    //  print("Error while traversing directory: ${result.stderr}");
    //  return null;
    //}
    List<String> lines = result.stdout.split('\n');
    List<Traverser> children = [];
    int charsConsumed = lines[0].length + 1; // +1 for the newline // ls -la prints the total size of the directory first. Which is bad.
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].isEmpty) {
        charsConsumed +=  1; // +1 for the newline
        continue;
      }
      RegExpMatch? parts = lsSplitter.firstMatch(lines[i]);
      if (parts == null) {
        print("Error while splitting ls output: ${lines[i]}");
        continue;
      }
      bool is_directory = parts.group(1)!.contains('d');
      String filename = parts.group(3)!;
      num size = num.parse(parts.group(2)!);
      if (filename.endsWith('.')) {
        charsConsumed += lines[i].length + 1; // +1 for the newline
        continue;
      }
      if (is_directory) {
        print("Traversing child: $path$filename/");
        charsConsumed += lines[i].length + 1; // +1 for the newline
        Traverser? child =
            await _traverseDirectory('$path${_fix_pull_filename(filename)}/');
        if (child != null) {
          children.add(child);
        }
      } else {
        //String uhoh = result.stdout.substring(charsConsumed, charsConsumed+ lines[i].length + 1);
        //print(uhoh);

        List<int> funnyChars = [];
        bool consumeFunny(){
          String cfilename = filename;
          if(result.stdout_funnies.isEmpty) return false;
          if(result.stdout_funnies[0]> charsConsumed && result.stdout_funnies[0] < charsConsumed + lines[i].length + 1){
            //our line has one of the funny characters
            funnyChars.add(result.stdout_funnies[0] - charsConsumed);
            result.stdout_funnies.removeAt(0);
            return true;
          }
          return false;
        }
        while(consumeFunny()){}
        charsConsumed += lines[i].length + 1;
        children.add(Traverser("$path/$filename", false, size: size, malformedChars: funnyChars));
      }
    }
    return Traverser(path, true, children: children);
  }

  static Future<bool> pullFile(String remotePath, String localPath) async {
    ProcessResult result = await Process.run(


        AdbUtils._adbPath,
        [
          '-s',
          AdbUtils._chosenDevice,
          'pull',
          (remotePath.replaceAll("\\", "").replaceAll("&", "^&")),
          localPath.replaceAll('&', '^&')
        ],
        runInShell: true);
    if (result.exitCode != 0) {
      print("Error while pulling file: ${result.stderr}");
      return false;
    }
    return true;
  }

  static num getRemoteFileSize(String remotePath) {
    ProcessResult result = Process.runSync(AdbUtils._adbPath, [
      '-s',
      AdbUtils._chosenDevice,
      'shell',
      'stat',
      '-c',
      '%s',
      remotePath
    ]);
    if (result.exitCode != 0) {
      print("Error while getting file size: ${result.stderr}");
      return -1;
    }
    return num.parse(result.stdout);
  }
}
