import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'file_library_models.dart';
import 'file_library_service.dart';

part 'file_library_bloc.freezed.dart';

class FileLibraryBloc extends Bloc<FileLibraryEvent, FileLibraryState> {
  FileLibraryBloc({
    FileLibraryService? service,
  })  : _service = service ?? FileLibraryService(),
        super(const FileLibraryState()) {
    on<FileLibraryEvent>(_onEvent);
  }

  final FileLibraryService _service;

  Future<void> _onEvent(
    FileLibraryEvent event,
    Emitter<FileLibraryState> emit,
  ) async {
    await event.when(
      started: () => _onStarted(emit),
      categoryChanged: (category) => _onCategoryChanged(category, emit),
      refreshFiles: () => _onRefreshFiles(emit),
      deleteFile: (fileId) => _onDeleteFile(fileId, emit),
      importPdfFile: () => _onImportPdfFile(emit),
      openFile: (fileItem) => _onOpenFile(fileItem, emit),
      sortChanged: (sortBy) => _onSortChanged(sortBy, emit),
    );
  }

  Future<void> _onStarted(Emitter<FileLibraryState> emit) async {
    emit(state.copyWith(isLoading: true));

    try {
      final files = await _service.getAllFiles();
      final sortedFiles = _sortFiles(files, state.sortBy);
      emit(state.copyWith(
        isLoading: false,
        files: files,
        filteredFiles: sortedFiles,
      ),);
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: e.toString(),
      ),);
    }
  }

  Future<void> _onCategoryChanged(
    FileLibraryCategory category,
    Emitter<FileLibraryState> emit,
  ) async {
    final filteredFiles = category == FileLibraryCategory.all
        ? state.files
        : state.files
            .where((file) => category.matchesFileType(file.fileType))
            .toList();
    
    final sortedFiles = _sortFiles(filteredFiles, state.sortBy);

    emit(state.copyWith(
      selectedCategory: category,
      filteredFiles: sortedFiles,
    ),);
  }

  Future<void> _onImportPdfFile(Emitter<FileLibraryState> emit) async {
    emit(state.copyWith(isImporting: true));

    try {
      final importedFile = await _service.importPdfFile();
      if (importedFile != null) {
        // 重新加载文件列表
        final files = await _service.getAllFiles();
        final filteredFiles = state.selectedCategory == FileLibraryCategory.all
            ? files
            : files
                .where((file) => state.selectedCategory.matchesFileType(file.fileType))
                .toList();
        
        final sortedFiles = _sortFiles(filteredFiles, state.sortBy);

        emit(state.copyWith(
          isImporting: false,
          files: files,
          filteredFiles: sortedFiles,
          successMessage: '文件上传成功：${importedFile.name}',
        ));
      } else {
        emit(state.copyWith(
          isImporting: false,
          infoMessage: '用户取消了文件选择',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isImporting: false,
        error: '文件上传失败：${e.toString()}',
      ));
    }
  }

  Future<void> _onOpenFile(
    FileLibraryItem fileItem,
    Emitter<FileLibraryState> emit,
  ) async {
    try {
      await _service.openPdfFile(fileItem);
      emit(state.copyWith(
        successMessage: '正在打开文件：${fileItem.name}',
      ));
    } catch (e) {
      emit(state.copyWith(
        error: '打开文件失败：${e.toString()}',
      ));
    }
  }

  Future<void> _onRefreshFiles(Emitter<FileLibraryState> emit) async {
    emit(state.copyWith(isLoading: true));

    try {
      final files = await _service.getAllFiles();
      final filteredFiles = state.selectedCategory == FileLibraryCategory.all
          ? files
          : files
              .where((file) =>
                  state.selectedCategory.matchesFileType(file.fileType),)
              .toList();
      
      final sortedFiles = _sortFiles(filteredFiles, state.sortBy);

      emit(state.copyWith(
        isLoading: false,
        files: files,
        filteredFiles: sortedFiles,
        error: null,
      ),);
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: e.toString(),
      ),);
    }
  }

  Future<void> _onDeleteFile(
    String fileId,
    Emitter<FileLibraryState> emit,
  ) async {
    try {
      await _service.deleteFile(fileId);

      final updatedFiles = state.files.where((f) => f.id != fileId).toList();
      final filteredFiles = state.selectedCategory == FileLibraryCategory.all
          ? updatedFiles
          : updatedFiles
              .where((file) =>
                  state.selectedCategory.matchesFileType(file.fileType),)
              .toList();
      
      final sortedFiles = _sortFiles(filteredFiles, state.sortBy);

      emit(state.copyWith(
        files: updatedFiles,
        filteredFiles: sortedFiles,
      ),);
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onSortChanged(
    String sortBy,
    Emitter<FileLibraryState> emit,
  ) async {
    final sortedFiles = _sortFiles(state.filteredFiles, sortBy);
    emit(state.copyWith(
      sortBy: sortBy,
      filteredFiles: sortedFiles,
    ));
  }

  List<FileLibraryItem> _sortFiles(List<FileLibraryItem> files, String sortBy) {
    final sortedFiles = List<FileLibraryItem>.from(files);
    
    switch (sortBy) {
      case '标题名称':
        sortedFiles.sort((a, b) => a.name.compareTo(b.name));
        break;
      case '大小':
        sortedFiles.sort((a, b) {
          final sizeA = a.size ?? 0;
          final sizeB = b.size ?? 0;
          return sizeB.compareTo(sizeA); // 从大到小
        });
        break;
      case '添加日期':
      default:
        sortedFiles.sort((a, b) {
          final dateA = a.createdAt ?? DateTime.now();
          final dateB = b.createdAt ?? DateTime.now();
          return dateB.compareTo(dateA); // 从新到旧
        });
        break;
    }
    
    return sortedFiles;
  }
}

@freezed
class FileLibraryEvent with _$FileLibraryEvent {
  const factory FileLibraryEvent.started() = _Started;
  const factory FileLibraryEvent.categoryChanged(FileLibraryCategory category) =
      _CategoryChanged;
  const factory FileLibraryEvent.refreshFiles() = _RefreshFiles;
  const factory FileLibraryEvent.deleteFile(String fileId) = _DeleteFile;
  const factory FileLibraryEvent.importPdfFile() = _ImportPdfFile;
  const factory FileLibraryEvent.openFile(FileLibraryItem fileItem) = _OpenFile;
  const factory FileLibraryEvent.sortChanged(String sortBy) = _SortChanged;
}

@freezed
class FileLibraryState with _$FileLibraryState {
  const factory FileLibraryState({
    @Default(FileLibraryCategory.all) FileLibraryCategory selectedCategory,
    @Default([]) List<FileLibraryItem> files,
    @Default([]) List<FileLibraryItem> filteredFiles,
    @Default(false) bool isLoading,
    @Default(false) bool isImporting,
    @Default('添加日期') String sortBy,
    String? error,
    String? successMessage,
    String? infoMessage,
  }) = _FileLibraryState;
}


