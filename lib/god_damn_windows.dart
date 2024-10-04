import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class Kernel32 {
  final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  late final int Function(
      Pointer<Utf16> lpApplicationName,
      Pointer<Utf16> lpCommandLine,
      Pointer<SECURITY_ATTRIBUTES> lpProcessAttributes,
      Pointer<SECURITY_ATTRIBUTES> lpThreadAttributes,
      int bInheritHandles,
      int dwCreationFlags,
      Pointer<Void> lpEnvironment,
      Pointer<Utf16> lpCurrentDirectory,
      Pointer<STARTUPINFO> lpStartupInfo,
      Pointer<PROCESS_INFORMATION> lpProcessInformation) CreateProcessW =
      _kernel32.lookupFunction<
          Int32 Function(
              Pointer<Utf16> lpApplicationName,
              Pointer<Utf16> lpCommandLine,
              Pointer<SECURITY_ATTRIBUTES> lpProcessAttributes,
              Pointer<SECURITY_ATTRIBUTES> lpThreadAttributes,
              Int32 bInheritHandles,
              Uint32 dwCreationFlags,
              Pointer<Void> lpEnvironment,
              Pointer<Utf16> lpCurrentDirectory,
              Pointer<STARTUPINFO> lpStartupInfo,
              Pointer<PROCESS_INFORMATION> lpProcessInformation),
          int Function(
              Pointer<Utf16> lpApplicationName,
              Pointer<Utf16> lpCommandLine,
              Pointer<SECURITY_ATTRIBUTES> lpProcessAttributes,
              Pointer<SECURITY_ATTRIBUTES> lpThreadAttributes,
              int bInheritHandles,
              int dwCreationFlags,
              Pointer<Void> lpEnvironment,
              Pointer<Utf16> lpCurrentDirectory,
              Pointer<STARTUPINFO> lpStartupInfo,
              Pointer<PROCESS_INFORMATION> lpProcessInformation)>('CreateProcessW');

  late final Function _createPipe = _kernel32.lookupFunction<
      Int32 Function(
          Pointer<IntPtr> hReadPipe,
          Pointer<IntPtr> hWritePipe,
          Pointer<SECURITY_ATTRIBUTES> lpPipeAttributes,
          Uint32 nSize),
      int Function(
          Pointer<IntPtr> hReadPipe,
          Pointer<IntPtr> hWritePipe,
          Pointer<SECURITY_ATTRIBUTES> lpPipeAttributes,
          int nSize)>('CreatePipe');

  late final Function readFile = _kernel32.lookupFunction<
      Int32 Function(IntPtr hFile, Pointer<Uint8> lpBuffer, Uint32 nNumberOfBytesToRead,
          Pointer<Uint32> lpNumberOfBytesRead, Pointer<Void> lpOverlapped),
      int Function(int hFile, Pointer<Uint8> lpBuffer, int nNumberOfBytesToRead,
          Pointer<Uint32> lpNumberOfBytesRead, Pointer<Void> lpOverlapped)>('ReadFile');

  int createProcess(String commandLine, Pointer<IntPtr> hStdoutRead, Pointer<IntPtr> hStderrRead) {
    final lpCommandLine = commandLine.toNativeUtf16();
    final lpStartupInfo = calloc<STARTUPINFO>();
    final lpProcessInformation = calloc<PROCESS_INFORMATION>();
    final sa = calloc<SECURITY_ATTRIBUTES>();
    final hStdoutWrite = calloc<IntPtr>();
    final hStderrWrite = calloc<IntPtr>();

    try {
      sa.ref.nLength = sizeOf<SECURITY_ATTRIBUTES>();
      sa.ref.bInheritHandle = TRUE;
      sa.ref.lpSecurityDescriptor = nullptr;

      if (_createPipe(hStdoutRead, hStdoutWrite, sa, 0) == 0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }
      if (_createPipe(hStderrRead, hStderrWrite, sa, 0) == 0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }

      lpStartupInfo.ref.cb = sizeOf<STARTUPINFO>();
      lpStartupInfo.ref.hStdOutput = hStdoutWrite.value;
      lpStartupInfo.ref.hStdError = hStderrWrite.value;
      lpStartupInfo.ref.dwFlags |= STARTF_USESTDHANDLES;

      final result = CreateProcessW(
        nullptr,
        lpCommandLine,
        nullptr,
        nullptr,
        TRUE,
        CREATE_NO_WINDOW,
        nullptr,
        nullptr,
        lpStartupInfo,
        lpProcessInformation,
      );

      if (result != 0) {
        var lastError = HRESULT_FROM_WIN32(GetLastError());
        if (lastError != 0) {
          throw WindowsException(lastError);
        }
      }

      return lpProcessInformation.ref.dwProcessId;
    } finally {
      free(lpCommandLine);
      free(lpStartupInfo);
      free(lpProcessInformation);
      free(sa);
      CloseHandle(hStdoutWrite.value);
      CloseHandle(hStderrWrite.value);
      free(hStdoutWrite);
      free(hStderrWrite);
    }
  }

  String readPipe(int hPipe) {
    final bufferSize = 4096;
    final buffer = calloc<Uint8>(bufferSize);
    final bytesRead = calloc<Uint32>();
    final output = StringBuffer();

    try {
      while (true) {
        final result = readFile(hPipe, buffer, bufferSize, bytesRead, nullptr);
        if (result == 0 || bytesRead.value == 0) break;
        
        final data = buffer.asTypedList(bytesRead.value);
        output.write(String.fromCharCodes(data));
      }
    } finally {
      free(buffer);
      free(bytesRead);
    }

    return output.toString();
  }
}