import 'dart:core';
import 'dart:io';
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
         Process.runSync("where", ['adb'])
            .stdout
            .split('\n')
            .forEach((element) {
              if (element.contains('adb.exe') && adbPath.isEmpty) {
                adbPath = element;
                
              }
            });
      } else if (Platform.isLinux || Platform.isMacOS) {
        Process.runSync("which", ['adb'])
            .stdout
            .split('\n')
            .forEach((element) {
              if (element.contains('adb')) {
                adbPath = element;
              }
            });
      }
      _adbPath = adbPath;
      return adbPath;
    }

    static Future<List<String>> queryDevices()  async{
      List<String> devices = [];
      ProcessResult result = await Process.run(_adbPath, ['devices'], runInShell: true);
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
      return filename.replaceAll(" ", "\\ ").replaceAll("(", "\\(").replaceAll(")", "\\)");
    }

    static Future<List<String>> queryDeviceNames() async {
      List<String> deviceNames = [];
      for (String device in _devices) {
        ProcessResult result = await Process.run(_adbPath, ['-s', device, 'shell', 'getprop', 'ro.product.model'], runInShell: true);
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
      ProcessResult result = await Process.run(_adbPath, ['-s', _chosenDevice, 'shell', 'ls', path], runInShell: true);
      return result.exitCode == 0;
    }
    static Future<Traverser?> Traverse_Remote(String path) async{
      return _traverseDirectory(path);
    }

    static Future<Traverser?> _traverseDirectory(String path) async {
      RegExp lsSplitter = RegExp(r'([dwrx-]{10})\s{1,}\d+\s+\w+\s+\w+\s+(\d+)\s[\d-]+\s[\d:]+\s(.+)\n*');
      ProcessResult result = await Process.run(_adbPath, ['-s', _chosenDevice, 'shell', 'ls', "-la" , '$path'], runInShell: true);
      if (result.exitCode != 0) {
        print("Error while traversing directory: ${result.stderr}");
        return null;
      }
      List<String> lines = result.stdout.split('\n');
      List<Traverser> children = [];
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
      if(filename.endsWith('.')) {
        continue;
      }
      if (is_directory) {
        //print("Traversing child: $path$filename/");
        Traverser? child = await _traverseDirectory('$path${_fix_pull_filename(filename)}/');
        if (child != null) {
        children.add(child);
        }
      } else {
        //print("adding file $path$filename");
        children.add(Traverser("$path/$filename", false, size: size));
      }
      }
      return Traverser(path, true, children: children);
    }

  static Future<bool> pullFile(String remotePath, String localPath) async {
    ProcessResult result = await Process.run(AdbUtils._adbPath, ['-s', AdbUtils._chosenDevice, 'pull', remotePath.replaceAll("\\", ""), localPath], runInShell: true);
    if (result.exitCode != 0) {
      print("Error while pulling file: ${result.stderr}");
      return false;
    }
    return true;
  }
  static num getRemoteFileSize(String remotePath) {
    ProcessResult result = Process.runSync(AdbUtils._adbPath, ['-s', AdbUtils._chosenDevice, 'shell', 'stat', '-c', '%s', remotePath]);
    if (result.exitCode != 0) {
      print("Error while getting file size: ${result.stderr}");
      return -1;
    }
    return num.parse(result.stdout);
  }
}
