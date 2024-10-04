import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:betterbetteradbsync/god_damn_windows.dart';
import 'package:betterbetteradbsync/pair.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';


// a cleanup here would be nice, but I'm too lazy to do it right now.

class AdbCommandExecutor {
  final Kernel32 _kernel32 = Kernel32();
  late final String _adbPath;

  AdbCommandExecutor() {
    _adbPath = _findAdbPath();
  }

  static final Map<int,int> _funnyChars = {
    160: 32, // Non-breaking space => space // Why would you ever, ever do this? Are you a sadist or something?
  };
  static final List<int> _utf8ControlChars = [227];
  //final _funnyMark = utf8.encode("_IAMVERYFUNNY");
  Pair<Uint8List, List<int>> _fixfunnycharacters(Uint8List input) {
    List<int> funnyChars = _funnyChars.keys.toList();
    List<int> fixedChars = _funnyChars.values.toList();
    List<int> funnyIndexes = [];
    for (int i = 0; i < input.length; i++) {
      if (funnyChars.contains(input[i])) {
        Uint8List prevthree = input.sublist(i-2, i);
        bool wehascontrolchar = false;
        for (int j = 0; j < prevthree.length; j++) {
          if (_utf8ControlChars.contains(prevthree[j])) {
            //print("Skipping this character because it's a wide character");
            wehascontrolchar = true;
            break;
          }
        }
        if(wehascontrolchar) continue;
        //print("Fixed a funny instance: ${utf8.decode(input.sublist(i-10, i+10))}");
        input[i] = fixedChars[funnyChars.indexOf(input[i])];
        funnyIndexes.add(i);
      }
    }
    return Pair(input, funnyIndexes);
  }

  Future<void> SpawnADBServer() async {
    final hStdoutRead = calloc<IntPtr>();
    final hStderrRead = calloc<IntPtr>();
    _kernel32.createProcess("$_adbPath start-server", hStdoutRead, hStderrRead);
    CloseHandle(hStdoutRead.value);
    CloseHandle(hStderrRead.value);
  }

  String _findAdbPath() {
    final result = Process.runSync('where', ['adb.exe']);
    if (result.exitCode != 0) {
      throw Exception('ADB not found in PATH');
    }
    return result.stdout.toString().split("\n")[0].trim();
  }

  Future<AdbCommandResult_RAW> executeAdbCommand_RAW(String command) async {
    Kernel32 kernel32 = Kernel32();
    final fullCommand = '$_adbPath $command';
    final si = calloc<STARTUPINFO>();
    final pi = calloc<PROCESS_INFORMATION>();
    final hStdoutRead = calloc<IntPtr>();
    final hStdoutWrite = calloc<IntPtr>();
    final hStderrRead = calloc<IntPtr>();
    final hStderrWrite = calloc<IntPtr>();

    try {
      // Create pipes for stdout and stderr
      final sa = calloc<SECURITY_ATTRIBUTES>()
        ..ref.nLength = sizeOf<SECURITY_ATTRIBUTES>()
        ..ref.bInheritHandle = TRUE;

      if (CreatePipe(hStdoutRead, hStdoutWrite, sa, 0) == 0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }
      if (CreatePipe(hStderrRead, hStderrWrite, sa, 0) == 0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }

      // Ensure the read handles are not inherited
      SetHandleInformation(hStdoutRead.value, HANDLE_FLAG_INHERIT, 0);
      SetHandleInformation(hStderrRead.value, HANDLE_FLAG_INHERIT, 0);

      // Set up process startup information
      si.ref.cb = sizeOf<STARTUPINFO>();
      si.ref.hStdOutput = hStdoutWrite.value;
      si.ref.hStdError = hStderrWrite.value;
      si.ref.dwFlags |= STARTF_USESTDHANDLES;

      // Create the process
      final lpCommandLine = fullCommand.toNativeUtf16();
      if (kernel32.CreateProcessW(
            nullptr,
            lpCommandLine,
            nullptr,
            nullptr,
            TRUE,
            CREATE_NO_WINDOW,
            nullptr,
            nullptr,
            si,
            pi,
          ) ==
          0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }

      // Close pipe write ends
      CloseHandle(hStdoutWrite.value);
      CloseHandle(hStderrWrite.value);

      // Read output asynchronously
      final stdoutFuture = await _readPipeAsyncRaw(hStdoutRead.value);
      final stderrFuture = _readPipeAsyncRaw(hStderrRead.value);

      // Wait for the process to complete
      final processExitCode = Completer<int>();
      Timer.periodic(Duration(milliseconds: 100), (timer) {
        final exitCode = calloc<DWORD>();
        try {
          if (GetExitCodeProcess(pi.ref.hProcess, exitCode) != 0) {
            if (exitCode.value != STILL_ACTIVE) {
              processExitCode.complete(exitCode.value);
              timer.cancel();
            }
          }
        } finally {
          free(exitCode);
        }
      });
       // Wait for both the process to complete and the output to be fully read
      await Future.wait([processExitCode.future, stderrFuture]);

      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;

      return AdbCommandResult_RAW(stdout, stderr);
    } finally {
      // Clean up resources
      CloseHandle(pi.ref.hProcess);
      CloseHandle(pi.ref.hThread);
      CloseHandle(hStdoutRead.value);
      CloseHandle(hStdoutWrite.value);
      CloseHandle(hStderrRead.value);
      CloseHandle(hStderrWrite.value);
      free(si);
      free(pi);
      free(hStdoutRead);
      free(hStdoutWrite);
      free(hStderrRead);
      free(hStderrWrite);
    }
  }

  String escapeSpecialCharacters(String input) {
    return input
        .replaceAll("&", "\\&")
        .replaceAll("(", "\\(")
        .replaceAll(")", "\\)");
  }
  Future<AdbCommandResult> executeAdbCommand(String command) async {
    var res = await executeAdbCommand_RAW(  escapeSpecialCharacters(command));
    var stdoutFix = _fixfunnycharacters(res.stdout);
    var stderrFix = _fixfunnycharacters(res.stderr);
    return AdbCommandResult(utf8.decode(stdoutFix.first), utf8.decode(stderrFix.first), stdout_funnies: stdoutFix.second, stderr_funnies: stderrFix.second);
  }

  Future<AdbCommandResult> sexecuteAdbCommand(String command) async {
    Kernel32 kernel32 = Kernel32();
    final fullCommand = '$_adbPath $command';
    final si = calloc<STARTUPINFO>();
    final pi = calloc<PROCESS_INFORMATION>();
    final hStdoutRead = calloc<IntPtr>();
    final hStdoutWrite = calloc<IntPtr>();
    final hStderrRead = calloc<IntPtr>();
    final hStderrWrite = calloc<IntPtr>();

    try {
      // Create pipes for stdout and stderr
      final sa = calloc<SECURITY_ATTRIBUTES>()
        ..ref.nLength = sizeOf<SECURITY_ATTRIBUTES>()
        ..ref.bInheritHandle = TRUE;

      if (CreatePipe(hStdoutRead, hStdoutWrite, sa, 0) == 0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }
      if (CreatePipe(hStderrRead, hStderrWrite, sa, 0) == 0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }

      // Ensure the read handles are not inherited
      SetHandleInformation(hStdoutRead.value, HANDLE_FLAG_INHERIT, 0);
      SetHandleInformation(hStderrRead.value, HANDLE_FLAG_INHERIT, 0);

      // Set up process startup information
      si.ref.cb = sizeOf<STARTUPINFO>();
      si.ref.hStdOutput = hStdoutWrite.value;
      si.ref.hStdError = hStderrWrite.value;
      si.ref.dwFlags |= STARTF_USESTDHANDLES;

      // Create the process
      final lpCommandLine = fullCommand.toNativeUtf16();
      if (kernel32.CreateProcessW(
            nullptr,
            lpCommandLine,
            nullptr,
            nullptr,
            TRUE,
            CREATE_NO_WINDOW,
            nullptr,
            nullptr,
            si,
            pi,
          ) ==
          0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }

      // Close pipe write ends
      CloseHandle(hStdoutWrite.value);
      CloseHandle(hStderrWrite.value);

      // Read output asynchronously
      final stdoutFuture = await _readPipeAsync(hStdoutRead.value); //Let's read this first.
      final stderrFuture = _readPipeAsync(hStderrRead.value);
      //final stderrFuture = Future<String>.delayed(Duration(seconds: 0), () => "");

      // Wait for the process to complete
      final processExitCode = Completer<int>();
      Timer.periodic(Duration(milliseconds: 100), (timer) {
        final exitCode = calloc<DWORD>();
        try {
          if (GetExitCodeProcess(pi.ref.hProcess, exitCode) != 0) {
            if (exitCode.value != STILL_ACTIVE) {
              processExitCode.complete(exitCode.value);
              timer.cancel();
            }
          }
        } finally {
          free(exitCode);
        }
      });

      // Wait for both the process to complete and the output to be fully read
      await Future.wait([processExitCode.future, stderrFuture]);

      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;

      return AdbCommandResult(stdout, stderr);
    } finally {
      // Clean up resources
      CloseHandle(pi.ref.hProcess);
      CloseHandle(pi.ref.hThread);
      CloseHandle(hStdoutRead.value);
      CloseHandle(hStdoutWrite.value);
      CloseHandle(hStderrRead.value);
      CloseHandle(hStderrWrite.value);
      free(si);
      free(pi);
      free(hStdoutRead);
      free(hStdoutWrite);
      free(hStderrRead);
      free(hStderrWrite);
    }
  }

  Future<Uint8List> _readPipeAsyncRaw(int hPipe) async {
    final completer = Completer<Uint8List>();
    var output = Uint8List(0);

    void read() {
      final buffer = calloc<Uint8>(4096 * 20);
      final bytesRead = calloc<DWORD>();

      try {
        final success = ReadFile(hPipe, buffer, 4096 * 20, bytesRead, nullptr);
        if (success == 0 || bytesRead.value == 0) {
          //output = _fixfunnycharacters(output); //Fix funny characters, because devs are funny, haha we put nbsp in our filenames.
          completer.complete(output);
          return;
        }

        final data = buffer.asTypedList(bytesRead.value);
        output = Uint8List.fromList([...output, ...data]); 

        read();
      } finally {
        free(buffer);
        free(bytesRead);
      }
    }

    read();

    return completer.future;
  }

  Future<String> _readPipeAsync(int hPipe) async {
    final completer = Completer<String>();
    final output = StringBuffer();
    Uint8List uint8Buffer = Uint8List(0);

    void read() {
      //print("Reading from pipe");
      final buffer = calloc<Uint8>(4096 * 20);
      final bytesRead = calloc<DWORD>();

      try {
        final success = ReadFile(hPipe, buffer, 4096 * 20, bytesRead, nullptr);
        if (success == 0 || bytesRead.value == 0) {
          String s = utf8.decode(uint8Buffer);
          completer.complete(s);
          return;
        }
        //print("Bytes read: ${bytesRead.value}");

        final data = buffer.asTypedList(bytesRead.value);
        uint8Buffer = Uint8List.fromList(uint8Buffer + data);
        output.write(String.fromCharCodes(data));
        //print("Output: ${output.toString()}");

        // Continue reading
        //Future.microtask(read);
        read();
      } finally {
        free(buffer);
        free(bytesRead);
      }
    }

    // Start reading
    read();

    return completer.future;
  }
}

class FunnyFixResult {
  final Uint8List fixed;
  final List<int> funnyIndexes;
  FunnyFixResult(this.fixed, this.funnyIndexes);
}
class AdbCommandResult {
  final String stdout;
  final List<int> stdout_funnies;
  final String stderr;
  final List<int> stderr_funnies;

  AdbCommandResult(this.stdout, this.stderr,{this.stdout_funnies = const [], this.stderr_funnies = const []});
}

class AdbCommandResult_RAW {
  final Uint8List stdout;
  final Uint8List stderr;

  AdbCommandResult_RAW(this.stdout, this.stderr);
}

