import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:betterbetteradbsync/adb_utils.dart';
import 'package:betterbetteradbsync/w32_adb_executor.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AdbCommandExecutor adbExecutor;

  setUp(() {
    adbExecutor = AdbCommandExecutor();
  });

  test('List Screenshots directory', () async {
    bool isNotStandard(String inp) {
      RegExp regExp = RegExp(r'[^\x00-\x7F]');
      return regExp.hasMatch(inp);
    }
    print("Let's begin");
    var tree = await AdbUtils.treeRemoteFiles("/sdcard/Pictures/Screenshots");
    for(var line in tree) {
      if(isNotStandard(line)){
        print(line);
      }
    }
    print("Traversed");
    for (var i = 0; i < tree.length; i++) {
      if(tree[i].contains("//ADB_")){
        print("Found the problematic entry");
        print(tree[i-1]);
        print(tree[i]);
        print(tree[i+1]);
      }
    }
    return;

    var res = await adbExecutor.executeAdbCommand('shell ls "/sdcard/Pictures/Screenshots"');
    var modifi = res.stdout;
    print('stdout: ${res.stdout}');
    print('stderr: ${res.stderr}');
    print("-------------------");
    expect(res.stderr, isEmpty, reason: 'The command should not produce any error output');
    expect(res.stdout, isNotEmpty, reason: 'The Screenshots directory should not be empty');
    var spl = modifi.split('\n');
    for (var i = 0; i < spl.length; i++) {
      if(isNotStandard(spl[i])) {
        print("Non-standard file name: ${spl[i]}");
      }
    }
    return;




    var result = await adbExecutor.executeAdbCommand_RAW('shell ls "/sdcard/"');
    var modified = result.stdout;
    //print('stdout: ${result.stdout}');
    //print('stderr: ${result.stderr}');
    //print("-------------------");
    expect(result.stderr, isEmpty, reason: 'The command should not produce any error output');
    expect(result.stdout, isNotEmpty, reason: 'The Screenshots directory should not be empty');

    List<int> newLineIndexes = [];
    for (int i = 0; i < result.stdout.length; i++) {
      if (result.stdout[i] == 10) {
        newLineIndexes.add(i);
      }
    }
    print("Number of new lines: ${newLineIndexes.length}");
    for (int i = 0; i < newLineIndexes.length; i++) {
      Uint8List fileName = Uint8List.fromList(result.stdout.sublist(i == 0 ? 0 : newLineIndexes[i - 1] + 1, newLineIndexes[i]));
      //print(fileName); //Rest in piece my console...
      String decodedFileName = utf8.decode(fileName);
      if(isNotStandard(decodedFileName)) {
        print("Non-standard file name: $decodedFileName");
      }
    }

    //final fileNames = modified.split('\n').where((line) => line.isNotEmpty);
    //for (final fileName in fileNames) {
    //  if(isNotStandard(fileName)) {
    //    print("Non-standard file name: $fileName");
    //  }
    //}
    //expect(true, true);
  }, timeout: const Timeout(Duration(seconds: 500)));

  test('Check ADB server is running', () async {
    final result = await adbExecutor.executeAdbCommand('devices');
    
    print('stdout: ${result.stdout}');
    print('stderr: ${result.stderr}');

    expect(result.stderr, isEmpty, reason: 'The command should not produce any error output');
    expect(result.stdout, contains('List of devices attached'), reason: 'The output should contain the list of devices');
    
    final lines = result.stdout.split('\n').where((line) => line.trim().isNotEmpty).toList();
    expect(lines.length, greaterThan(1), reason: 'At least one device should be connected');
  }, timeout: const Timeout(Duration(seconds: 2))); // 15-second timeout

  test('Long-running command test', () async {
    // This test is designed to take longer than its timeout
    final result = await adbExecutor.executeAdbCommand('shell sleep 20'); // This command will sleep for 20 seconds
    
    // This line should not be reached if the timeout works correctly
    fail('Test did not timeout as expected');
  }, timeout: const Timeout(Duration(seconds: 10))); // 10-second timeout
}