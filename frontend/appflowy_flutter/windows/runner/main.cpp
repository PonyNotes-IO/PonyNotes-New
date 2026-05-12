#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>

#include <cstdlib>
#include <fstream>
#include <string>
#include <utility>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

std::string WideStringToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return "";
  }

  int size_needed = WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
      nullptr, 0, nullptr, nullptr);
  if (size_needed <= 0) {
    return "";
  }

  std::string result(size_needed, '\0');
  WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
      result.data(), size_needed, nullptr, nullptr);
  return result;
}

void TrimWrappingQuote(std::wstring& value) {
  if (!value.empty() && value.front() == L'"') {
    value = value.substr(1);
  }
  if (!value.empty() && value.back() == L'"') {
    value.pop_back();
  }
}

std::string ExtractUrlFromCommandLine() {
  LPWSTR cmd_line = GetCommandLineW();
  if (cmd_line == nullptr) {
    return "";
  }

  OutputDebugStringW(L"[DeepLink] Raw command line: ");
  OutputDebugStringW(cmd_line);
  OutputDebugStringW(L"\n");

  std::wstring command_line(cmd_line);
  size_t pos = command_line.find(L"ponynotes://");
  if (pos != std::wstring::npos) {
    std::wstring url = command_line.substr(pos);
    TrimWrappingQuote(url);
    OutputDebugStringW(L"[DeepLink] Found URL in raw command line\n");
    return WideStringToUtf8(url);
  }

  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(cmd_line, &argc);
  if (argv != nullptr) {
    for (int i = 1; i < argc; i++) {
      std::wstring arg(argv[i]);
      if (arg.find(L"ponynotes://") == 0) {
        TrimWrappingQuote(arg);
        LocalFree(argv);
        OutputDebugStringW(L"[DeepLink] Found URL in parsed arguments\n");
        return WideStringToUtf8(arg);
      }
    }
    LocalFree(argv);
  }

  OutputDebugStringW(L"[DeepLink] No ponynotes:// URL found\n");
  return "";
}

std::string CheckPendingDeepLink() {
  char* app_data_env = std::getenv("APPDATA");
  if (app_data_env == nullptr) {
    return "";
  }

  std::string file_path =
      std::string(app_data_env) + "\\PonyNotes\\deep_link.txt";

  std::ifstream in_file(file_path);
  if (!in_file.is_open()) {
    return "";
  }

  std::string url;
  std::getline(in_file, url);
  in_file.close();

  if (!url.empty() && url.find("ponynotes://") == 0) {
    std::ofstream out_file(file_path, std::ios::trunc);
    out_file.close();

    OutputDebugStringW(L"[DeepLink] Read pending URL from file\n");
    return url;
  }

  return "";
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  std::string extracted_url = ExtractUrlFromCommandLine();

  if (extracted_url.empty()) {
    extracted_url = CheckPendingDeepLink();
    if (!extracted_url.empty()) {
      OutputDebugStringW(L"[DeepLink] Got URL from pending file\n");
    }
  }

  HANDLE h_mutex_instance = CreateMutex(NULL, TRUE, L"PonyNotesMutex");
  bool is_first_instance = (GetLastError() != ERROR_ALREADY_EXISTS);

  if (!is_first_instance) {
    if (!extracted_url.empty()) {
      char* app_data_env = std::getenv("APPDATA");
      if (app_data_env != nullptr) {
        std::string file_path =
            std::string(app_data_env) + "\\PonyNotes\\deep_link.txt";
        std::ofstream out_file(file_path);
        if (out_file.is_open()) {
          out_file << extracted_url;
          out_file.close();
          OutputDebugStringW(L"[DeepLink] Wrote URL to pipe file\n");
        }
      }
    }

    HWND hwnd = FindWindowA(NULL, "PonyNotes");
    if (hwnd != NULL) {
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
      SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    }

    ReleaseMutex(h_mutex_instance);
    return 0;
  }

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  if (!extracted_url.empty()) {
    command_line_arguments.insert(command_line_arguments.begin(), extracted_url);
  }

  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);

  if (!window.Create(L"PonyNotes", origin, size)) {
    ReleaseMutex(h_mutex_instance);
    return EXIT_FAILURE;
  }

  window.Show();
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseMutex(h_mutex_instance);
  return EXIT_SUCCESS;
}
