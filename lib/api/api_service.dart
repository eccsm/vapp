import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'package:logger/logger.dart';

import '../database/models/note.dart';
import 'models/note.dart';
import 'models/transcription_response.dart';

class ApiService {
  final Dio _dio;
  final String _baseUrl;
  final Logger _logger = Logger();
  
  ApiService({required Dio dio, required String baseUrl})
      : _dio = dio,
        _baseUrl = baseUrl {
    _dio.options.baseUrl = _baseUrl;
    
    // Add authorization interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Add token if available
          final token = _getAuthToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
  }
  
  String? _getAuthToken() {
    // Get token from secure storage
    // This should be implemented using flutter_secure_storage
    return null;
  }
  
  // Update the transcribeAudio method
Future<TranscriptionResponse> transcribeAudio(File audioFile, String? prompt) async {
  try {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        audioFile.path,
        filename: audioFile.path.split('/').last,
      ),
      'model': 'whisper-1',
      'language': 'en', // Specify English as the language
      if (prompt != null) 'prompt': prompt,
    });
    
    final response = await _dio.post(
      '/api/audio/transcribe',
      data: formData,
      options: Options(
        validateStatus: (status) => status! < 500, // Accept 400 responses to read error message
      ),
    );
    
    // Check if response indicates an error
    if (response.statusCode == 400) {
      final errorData = response.data;
      String errorMessage = "Unknown error";
      
      if (errorData is Map && errorData.containsKey('error')) {
        errorMessage = errorData['error'];
      }
      
      _logger.e('API error: $errorMessage');
      throw Exception(errorMessage);
    }
    
    return TranscriptionResponse.fromJson(response.data);
  } catch (e) {
    _logger.e('Error transcribing audio: $e');
    throw Exception('Failed to transcribe audio: $e');
  }
}

// Update the transcribeAudioBytes method
Future<TranscriptionResponse> transcribeAudioBytes(
  Uint8List audioBytes, {
  required String fileName,
  String? title,
}) async {
  try {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        audioBytes,
        filename: fileName,
        contentType: MediaType('audio', 'webm'),
      ),
      'model': 'whisper-1',
      'language': 'en', // Specify English as the language
      if (title != null) 'prompt': title,
    });

    final response = await _dio.post(
      '/api/audio/transcribe',
      data: formData,
    );

    return TranscriptionResponse.fromJson(response.data);
  } catch (e) {
    _logger.e('Error transcribing audio bytes: $e');
    throw Exception('Failed to transcribe audio bytes: $e');
  }
}
  

  Future<ApiNote> syncNote(Notes note) async {
    try {
      final response = await _dio.post(
        '/api/notes',
        data: {
          'title': note.title,
          'content': note.content,
          'createdAt': note.createdAt.toString(),
          'updatedAt': note.updatedAt.toString(),
          'categoryId': note.categoryId,
        },
      );
      
      return ApiNote.fromJson(response.data);
    } catch (e) {
      _logger.e('Error syncing note: $e');
      throw Exception('Failed to sync note: $e');
    }
  }
  
  // Get all notes from the server
  Future<List<ApiNote>> getNotes() async {
    try {
      final response = await _dio.get('/api/notes');
      
      return (response.data as List)
        .map((data) => ApiNote.fromJson(data))
        .toList();
    } catch (e) {
      _logger.e('Error fetching notes: $e');
      throw Exception('Failed to fetch notes: $e');
    }
  }
  
  // Get a single note by ID
  Future<ApiNote> getNoteById(String id) async {
    try {
      final response = await _dio.get('/api/notes/$id');
      
      return ApiNote.fromJson(response.data);
    } catch (e) {
      _logger.e('Error fetching note: $e');
      throw Exception('Failed to fetch note: $e');
    }
  }
  
  // Delete a note
  Future<void> deleteNote(String id) async {
    try {
      await _dio.delete('/api/notes/$id');
    } catch (e) {
      _logger.e('Error deleting note: $e');
      throw Exception('Failed to delete note: $e');
    }
  }
  }

  final apiServiceProvider = Provider<ApiService>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: 'http://192.168.1.5:8080',
    connectTimeout: Duration(seconds: 5), 
    receiveTimeout: Duration(seconds: 5),
  ));
  
  dio.interceptors.add(LogInterceptor(
    requestBody: true,
    responseBody: true,
  ));
  
  return ApiService(
    dio: dio,
    baseUrl: 'http://192.168.1.10:8080',
  );
});


