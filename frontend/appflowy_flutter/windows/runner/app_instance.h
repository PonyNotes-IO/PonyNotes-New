#ifndef RUNNER_APP_INSTANCE_H_
#define RUNNER_APP_INSTANCE_H_

// Debug and installed release must launch independently.
#ifdef _DEBUG
inline constexpr wchar_t kInstanceMutexName[] = L"PonyNotesDebugMutex";
inline constexpr wchar_t kWindowClassName[] = L"PONYNOTES_DEBUG_WIN32_WINDOW";
inline constexpr wchar_t kWindowTitle[] = L"PonyNotes (Debug)";
inline constexpr char kDeepLinkFileName[] = "deep_link_debug.txt";
#else
inline constexpr wchar_t kInstanceMutexName[] = L"PonyNotesMutex";
inline constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
inline constexpr wchar_t kWindowTitle[] = L"PonyNotes";
inline constexpr char kDeepLinkFileName[] = "deep_link.txt";
#endif

#endif  // RUNNER_APP_INSTANCE_H_
