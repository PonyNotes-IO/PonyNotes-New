#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlwapi.h>
#include <shellapi.h>
#include <fstream>
#include <sstream>
#include <cstdlib>
#include <iostream>

#include "flutter_window.h"
#include "utils.h"

// 从命令行中提取 URL 参数
std::string ExtractUrlFromCommandLine() {
  // 获取原始命令行
  LPWSTR cmdLine = GetCommandLineW();
  if (cmdLine == nullptr) return "";

  // 打印原始命令行用于调试
  OutputDebugStringW(L"[DeepLink] Raw command line: ");
  OutputDebugStringW(cmdLine);
  OutputDebugStringW(L"\n");

  // 首先直接搜索原始命令行
  std::wstring cmdWstr(cmdLine);
  size_t pos = cmdWstr.find(L"ponynotes://");
  if (pos != std::wstring::npos) {
    std::wstring urlWstr = cmdWstr.substr(pos);
    
    // 去除可能的引号
    if (!urlWstr.empty() && urlWstr.front() == L'"') {
      urlWstr = urlWstr.substr(1);
    }
    if (!urlWstr.empty() && urlWstr.back() == L'"') {
      urlWstr.pop_back();
    }
    
    // 转换为 UTF-8
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, urlWstr.c_str(), (int)urlWstr.size(), NULL, 0, NULL, NULL);
    std::string urlStr(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, urlWstr.c_str(), (int)urlWstr.size(), &urlStr[0], size_needed, NULL, NULL);
    
    OutputDebugStringW(L"[DeepLink] Found URL in raw command line\n");
    return urlStr;
  }
  
  // 如果在原始命令行中找不到，尝试解析命令行参数
  int argc;
  wchar_t** argv = CommandLineToArgvW(cmdLine, &argc);
  if (argv != nullptr) {
    for (int i = 1; i < argc; i++) {
      std::wstring arg(argv[i]);
      if (arg.find(L"ponynotes://") == 0) {
        // 去除引号
        if (!arg.empty() && arg.front() == L'"') {
          arg = arg.substr(1);
        }
        if (!arg.empty() && arg.back() == L'"') {
          arg.pop_back();
        }
        
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, arg.c_str(), (int)arg.size(), NULL, 0, NULL, NULL);
        std::string urlStr(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, arg.c_str(), (int)arg.size(), &urlStr[0], size_needed, NULL, NULL);
        
        LocalFree(argv);
        OutputDebugStringW(L"[DeepLink] Found URL in parsed arguments\n");
        return urlStr;
      }
    }
    LocalFree(argv);
  }
  
  OutputDebugStringW(L"[DeepLink] No ponynotes:// URL found\n");
  return "";
}

// 检查是否有待处理的 deep link（用于主实例从文件读取）
std::string CheckPendingDeepLink() {
  char* appDataEnv = std::getenv("APPDATA");
  if (appDataEnv == nullptr) return "";
  
  std::string appData(appDataEnv);
  std::string filePath = appData + "\\PonyNotes\\deep_link.txt";
  
  std::ifstream inFile(filePath);
  if (inFile.is_open()) {
    std::string url;
    std::getline(inFile, url);
    inFile.close();
    
    if (!url.empty() && url.find("ponynotes://") == 0) {
      // 清空文件
      std::ofstream outFile(filePath, std::ios::trunc);
      outFile.close();
      
      OutputDebugStringW(L"[DeepLink] Read pending URL from file\n");
      return url;
    }
  }
  return "";
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  // 首先尝试从命令行提取 URL
  std::string extractedUrl = ExtractUrlFromCommandLine();
  
  // 如果命令行中没有 URL，检查是否有待处理的 deep link 文件
  if (extractedUrl.empty()) {
    extractedUrl = CheckPendingDeepLink();
    if (!extractedUrl.empty()) {
      OutputDebugStringW(L"[DeepLink] Got URL from pending file\n");
    }
  }
  
  // 创建互斥锁用于单实例检测
  HANDLE hMutexInstance = CreateMutex(NULL, TRUE, L"PonyNotesMutex");
  bool isFirstInstance = (GetLastError() != ERROR_ALREADY_EXISTS);

  if (!isFirstInstance)
  {
    // 有实例在运行，传递 URL 并尝试激活已有窗口
    if (!extractedUrl.empty()) {
      // 写入到文件供主实例读取
      char* appDataEnv = std::getenv("APPDATA");
      if (appDataEnv != nullptr) {
        std::string appData(appDataEnv);
        std::string filePath = appData + "\\PonyNotes\\deep_link.txt";
        std::ofstream outFile(filePath);
        if (outFile.is_open()) {
          outFile << extractedUrl;
          outFile.close();
          OutputDebugStringW(L"[DeepLink] Wrote URL to pipe file\n");
        }
      }
    }
    
    // 尝试找到并激活已有窗口
    HWND hwnd = FindWindowA(NULL, "PonyNotes");
    if (hwnd != NULL) {
      // 恢复窗口
      ShowWindow(hwnd, SW_RESTORE);
      // 激活窗口
      SetForegroundWindow(hwnd);
      // 置顶窗口
      SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    }
    
    ReleaseMutex(hMutexInstance);
    return 0;  // 退出新实例
  }

  // 获取命令行参数
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  
  // 如果从命令行提取到 URL，添加到参数列表
  if (!extractedUrl.empty()) {
    command_line_arguments.insert(command_line_arguments.begin(), extractedUrl);
  }
  
  //  Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);

  if (!window.Create(L"PonyNotes", origin, size))
  {
    ReleaseMutex(hMutexInstance);
    return EXIT_FAILURE;
  }

  window.Show();
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseMutex(hMutexInstance);
  return EXIT_SUCCESS;
}
