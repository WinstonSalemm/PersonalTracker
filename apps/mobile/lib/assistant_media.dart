import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:personal_tracker_command_parser/command_parser.dart';

class AssistantImageResolver {
  Future<AssistantPlan> enrich(AssistantPlan plan) async {
    return switch (plan.intent) {
      AssistantIntent.movies => _enrichMovies(plan),
      AssistantIntent.visual => _enrichVisual(plan),
      _ => Future.value(plan),
    };
  }

  Future<AssistantPlan> _enrichMovies(AssistantPlan plan) async {
    final movies = await Future.wait(
      plan.movies.map(
        (movie) async => movie.copyWith(
          imageUrl: await _findImage('${movie.title} фильм'),
        ),
      ),
    );
    return plan.copyWith(movies: movies);
  }

  Future<AssistantPlan> _enrichVisual(AssistantPlan plan) async {
    final query = plan.visualQuery ?? 'животное';
    final result = await _search(query);
    if (result == null) return plan;
    return plan.copyWith(
      visualTitle: result.title,
      visualDescription: result.description,
      visualImageUrl: result.imageUrl,
    );
  }

  Future<String?> _findImage(String query) async => (await _search(query))?.imageUrl;

  Future<_ImageResult?> _search(String query) async {
    try {
      final response = await http
          .get(
            Uri.https('ru.wikipedia.org', '/w/api.php', {
              'action': 'query',
              'generator': 'search',
              'gsrsearch': query,
              'gsrnamespace': '0',
              'gsrlimit': '1',
              'prop': 'pageimages|extracts',
              'piprop': 'thumbnail',
              'pithumbsize': '640',
              'exintro': '1',
              'explaintext': '1',
              'format': 'json',
              'origin': '*',
            }),
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'PersonalTrackerAssistant/0.1',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) return null;
      final pages = body['query']?['pages'];
      if (pages is! Map || pages.isEmpty) return null;
      final page = pages.values.first;
      if (page is! Map) return null;
      final thumbnail = page['thumbnail'];
      final imageUrl = thumbnail is Map ? thumbnail['source'] as String? : null;
      final title = page['title'] as String?;
      final description = page['extract'] as String?;
      if (imageUrl == null && description == null) return null;
      return _ImageResult(
        title: title ?? query,
        imageUrl: imageUrl,
        description: description,
      );
    } catch (_) {
      // Text-only responses remain fully usable offline or when the image
      // lookup is unavailable.
      return null;
    }
  }
}

class _ImageResult {
  const _ImageResult({required this.title, this.imageUrl, this.description});

  final String title;
  final String? imageUrl;
  final String? description;
}
