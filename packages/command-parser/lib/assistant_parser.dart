import 'package:personal_tracker_domain/domain.dart';

enum AssistantIntent { movies, visual, task, contact, call, telegram }

class MovieSuggestion {
  const MovieSuggestion({
    required this.title,
    required this.year,
    required this.genre,
    required this.tags,
    required this.description,
    this.imageUrl,
  });

  final String title;
  final int year;
  final String genre;
  final List<String> tags;
  final String description;
  final String? imageUrl;

  MovieSuggestion copyWith({String? imageUrl}) => MovieSuggestion(
    title: title,
    year: year,
    genre: genre,
    tags: tags,
    description: description,
    imageUrl: imageUrl ?? this.imageUrl,
  );
}

class AssistantPlan {
  const AssistantPlan({
    required this.intent,
    required this.originalText,
    this.movies = const [],
    this.visualQuery,
    this.visualTitle,
    this.visualDescription,
    this.visualImageUrl,
    this.taskTitle,
    this.dueAt,
    this.contactName,
    this.phone,
    this.telegramUsername,
    this.message,
  });

  final AssistantIntent intent;
  final String originalText;
  final List<MovieSuggestion> movies;
  final String? visualQuery;
  final String? visualTitle;
  final String? visualDescription;
  final String? visualImageUrl;
  final String? taskTitle;
  final DateTime? dueAt;
  final String? contactName;
  final String? phone;
  final String? telegramUsername;
  final String? message;

  bool get hasTarget =>
      (phone?.isNotEmpty ?? false) ||
      (telegramUsername?.isNotEmpty ?? false);

  String get title => switch (intent) {
    AssistantIntent.movies => 'Подборка для вечера',
    AssistantIntent.visual => 'Вот как это выглядит',
    AssistantIntent.task => 'Задача готова к сохранению',
    AssistantIntent.contact => 'Контакт сохранён',
    AssistantIntent.call => 'Контакт готов к звонку',
    AssistantIntent.telegram => 'Сообщение готово к отправке',
  };

  AssistantPlan copyWith({
    List<MovieSuggestion>? movies,
    String? visualTitle,
    String? visualDescription,
    String? visualImageUrl,
    String? contactName,
    String? phone,
    String? telegramUsername,
  }) => AssistantPlan(
    intent: intent,
    originalText: originalText,
    movies: movies ?? this.movies,
    visualQuery: visualQuery,
    visualTitle: visualTitle ?? this.visualTitle,
    visualDescription: visualDescription ?? this.visualDescription,
    visualImageUrl: visualImageUrl ?? this.visualImageUrl,
    taskTitle: taskTitle,
    dueAt: dueAt,
    contactName: contactName ?? this.contactName,
    phone: phone ?? this.phone,
    telegramUsername: telegramUsername ?? this.telegramUsername,
    message: message,
  );
}

class DeterministicAssistantParser {
  Future<AssistantPlan?> parse(String input) async {
    final value = input.trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();

    if (_isMovieRequest(lower)) return _movies(value, lower);
    if (_isVisualRequest(lower)) return _visual(value);
    if (_isContactRequest(lower)) return _contact(value);
    if (_isTelegramRequest(lower)) return _telegram(value);
    if (_isCallRequest(lower)) return _call(value);
    if (_isTaskRequest(lower)) return _task(value, lower);
    return null;
  }

  bool _isMovieRequest(String value) =>
      _containsAny(value, [
        'фильм',
        'фильмов',
        'кино',
        'movie',
        'подборк',
        'подбер',
        'посоветуй',
      ]) ||
      (_containsAny(value, ['комед', 'триллер', 'ужас', 'фантаст', 'романт']) &&
          _containsAny(value, ['вечер', 'посмотр', 'список']));

  bool _isVisualRequest(String value) => _containsAny(value, [
    'как выглядит',
    'покажи фото',
    'покажи картин',
    'фото ',
    'фотографи',
    'изображени',
    'животн',
  ]);

  bool _isTelegramRequest(String value) =>
      _containsAny(value, ['телеграм', 'telegram', 'тг', 'tg://']) &&
      _containsAny(value, ['напиш', 'сообщ', 'отправ']);

  bool _isContactRequest(String value) =>
      _containsAny(value, ['контакт']) &&
      _containsAny(value, ['запомн', 'сохран', 'добав']);

  bool _isCallRequest(String value) =>
      _containsAny(value, ['позвон', 'набери', 'набрать', 'call']) &&
      !_containsAny(value, ['позвонил', 'позвонила']);

  bool _isTaskRequest(String value) => _containsAny(value, [
    'задач',
    'напомн',
    'календар',
    'поставь',
    'запиши',
    'создай',
    'добавь',
    'встреч',
  ]);

  AssistantPlan _movies(String original, String lower) {
    final count = _requestedCount(lower);
    final tags = <String>{};
    final tagAliases = <String, String>{
      'комед': 'комедия',
      'смешн': 'комедия',
      'лёгк': 'лёгкое',
      'легк': 'лёгкое',
      'триллер': 'триллер',
      'ужас': 'ужасы',
      'романт': 'романтика',
      'фантаст': 'фантастика',
      'боевик': 'боевик',
      'драм': 'драма',
      'мульт': 'мультфильм',
      'семейн': 'семейное',
      'детектив': 'детектив',
      'приключ': 'приключения',
    };
    for (final entry in tagAliases.entries) {
      if (lower.contains(entry.key)) tags.add(entry.value);
    }
    final matching = _catalog.where(
      (movie) => tags.isEmpty || movie.tags.any(tags.contains),
    );
    final selected = <MovieSuggestion>[...matching];
    if (selected.length < count) {
      for (final movie in _catalog) {
        if (!selected.contains(movie)) selected.add(movie);
        if (selected.length >= count) break;
      }
    }
    return AssistantPlan(
      intent: AssistantIntent.movies,
      originalText: original,
      movies: selected.take(count).toList(),
    );
  }

  AssistantPlan _visual(String original) {
    var query = original
        .replaceFirst(
          RegExp(
            r'^.*?(как выглядит|покажи фото|покажи картинку|покажи изображение|фото|фотографию)\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(RegExp(r'^животное\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^животн\w*\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[?!.]+$'), '')
        .trim();
    if (query.isEmpty) query = 'животное';
    return AssistantPlan(
      intent: AssistantIntent.visual,
      originalText: original,
      visualQuery: query,
    );
  }

  AssistantPlan _task(String original, String lower) {
    final dueAt = _dateTime(lower);
    var title = original
        .replaceFirst(
          RegExp(
            r'^\s*(поставь|поставить|запиши|записать|создай|добавь|напомни|напомнить)(?:\s+задач[ау])?\s+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(r'\s*(в календарь|в календаре)\s*', caseSensitive: false),
          ' ',
        );
    title = title
        .replaceAll(
          RegExp(
            r'\s+(сегодня|завтра|послезавтра|в понедельник|во вторник|в среду|в четверг|в пятницу|в субботу|в воскресенье)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\s+в\s+\d{1,2}(?::\d{2})?', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+на\s+\d{1,2}\.\d{1,2}(?:\.\d{2,4})?'), '')
        .replaceAll(RegExp(r'\s+через\s+\d+\s+(?:минут|час\w*|дн\w*)'), '')
        .replaceAll(RegExp(r'\s+и\s+напомни.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (title.isEmpty) title = 'Новая задача';
    return AssistantPlan(
      intent: AssistantIntent.task,
      originalText: original,
      taskTitle: _capitalize(title),
      dueAt: dueAt,
    );
  }

  AssistantPlan _call(String original) {
    final phone = _phone(original);
    final contact = _contactName(original, phone);
    return AssistantPlan(
      intent: AssistantIntent.call,
      originalText: original,
      contactName: contact,
      phone: phone,
    );
  }

  AssistantPlan _contact(String original) {
    final phone = _phone(original);
    final username = RegExp(r'@([a-zA-Z0-9_]{3,})').firstMatch(original)?.group(1);
    return AssistantPlan(
      intent: AssistantIntent.contact,
      originalText: original,
      contactName: _contactName(original, phone),
      phone: phone,
      telegramUsername: username,
    );
  }

  AssistantPlan _telegram(String original) {
    final username = RegExp(r'@([a-zA-Z0-9_]{3,})').firstMatch(original)?.group(1);
    final phone = _phone(original);
    final message = _message(original, username, phone);
    return AssistantPlan(
      intent: AssistantIntent.telegram,
      originalText: original,
      telegramUsername: username,
      phone: phone,
      contactName: _contactName(original, phone),
      message: message.isEmpty ? original : message,
    );
  }

  int _requestedCount(String value) {
    final digit = RegExp(r'\b(\d{1,2})\b').firstMatch(value)?.group(1);
    if (digit != null) return int.parse(digit).clamp(1, 20).toInt();
    const words = <String, int>{
      'один': 1,
      'одну': 1,
      'два': 2,
      'две': 2,
      'три': 3,
      'четыре': 4,
      'пять': 5,
      'шесть': 6,
      'семь': 7,
      'восемь': 8,
      'девять': 9,
      'десять': 10,
    };
    for (final entry in words.entries) {
      if (value.contains(entry.key)) return entry.value;
    }
    return 5;
  }

  DateTime? _dateTime(String value) {
    final now = DateTime.now();
    var date = DateTime(now.year, now.month, now.day);
    final explicit = RegExp(r'\b(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?\b')
        .firstMatch(value);
    if (explicit != null) {
      final yearValue = int.tryParse(explicit.group(3) ?? '') ?? now.year;
      final year = yearValue < 100 ? 2000 + yearValue : yearValue;
      date = DateTime(year, int.parse(explicit.group(2)!), int.parse(explicit.group(1)!));
    } else if (value.contains('послезавтра')) {
      date = date.add(const Duration(days: 2));
    } else if (value.contains('завтра')) {
      date = date.add(const Duration(days: 1));
    } else {
      final weekdays = <String, int>{
        'понедельник': DateTime.monday,
        'вторник': DateTime.tuesday,
        'среду': DateTime.wednesday,
        'четверг': DateTime.thursday,
        'пятницу': DateTime.friday,
        'субботу': DateTime.saturday,
        'воскресенье': DateTime.sunday,
      };
      for (final entry in weekdays.entries) {
        if (value.contains(entry.key)) {
          var delta = (entry.value - now.weekday) % 7;
          if (delta == 0) delta = 7;
          date = date.add(Duration(days: delta));
          break;
        }
      }
    }
    final relative = RegExp(r'через\s+(\d+)\s+(минут\w*|час\w*|дн\w*)')
        .firstMatch(value);
    if (relative != null) {
      final amount = int.parse(relative.group(1)!);
      final unit = relative.group(2)!;
      return now.add(
        unit.startsWith('минут')
            ? Duration(minutes: amount)
            : unit.startsWith('час')
            ? Duration(hours: amount)
            : Duration(days: amount),
      );
    }
    final time = RegExp(r'(?:в|на)\s+(\d{1,2})(?::(\d{2}))?').firstMatch(value);
    if (time == null && explicit == null && !value.contains('завтра') && !value.contains('послезавтра') &&
        !value.contains('понедельник') && !value.contains('вторник') && !value.contains('среду') &&
        !value.contains('четверг') && !value.contains('пятницу') && !value.contains('субботу') &&
        !value.contains('воскресенье')) {
      return null;
    }
    return DateTime(
      date.year,
      date.month,
      date.day,
      time == null ? 9 : int.parse(time.group(1)!),
      time == null ? 0 : int.parse(time.group(2) ?? '0'),
    );
  }

  String? _phone(String value) {
    final match = RegExp(r'(\+?\d[\d\s().-]{6,}\d)').firstMatch(value);
    return match?.group(1)?.replaceAll(RegExp(r'[^\d+]'), '');
  }

  String? _contactName(String value, String? phone) {
    var name = value
        .replaceFirst(RegExp(r'^.*?(позвони|набери|написать|напиши|отправь|добавь|сохрани|запомни)\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'контакт(?:у|а)?\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'@\w+'), '')
        .replaceAll(RegExp(r'\+?\d[\d\s().-]{6,}\d'), '')
        .replaceAll(RegExp(r'\s+(?:в\s+)?(?:телеграм|telegram|тг).*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+(что|сообщение|текст):?.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[,.!?]+'), ' ')
        .trim();
    if (name.length > 40) name = name.substring(0, 40).trim();
    return name.isEmpty ? null : name;
  }

  String _message(String value, String? username, String? phone) {
    final explicit = RegExp(
      r'(?:сообщение|текст)\s*:?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (explicit != null) return explicit.group(1)!.trim();
    var message = value
        .replaceFirst(RegExp(r'^.*?(написать|напиши|отправь)\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'в\s+(телеграм|тг|telegram)\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'@\w+'), '')
        .replaceAll(RegExp(r'\+?\d[\d\s().-]{6,}\d'), '')
        .replaceFirst(RegExp(r'^(контакту\s+)?[^,]+,?\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^(что|сообщение|текст)\s*:?', caseSensitive: false), '')
        .trim();
    return message;
  }

  String _capitalize(String value) => value.isEmpty
      ? value
      : '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';

  bool _containsAny(String value, List<String> values) => values.any(value.contains);
}

const _catalog = <MovieSuggestion>[
  MovieSuggestion(title: '1+1', year: 2011, genre: 'драма / комедия', tags: ['комедия', 'драма', 'лёгкое'], description: 'Тёплая история дружбы и нового начала.'),
  MovieSuggestion(title: 'Отель «Гранд Будапешт»', year: 2014, genre: 'комедия / приключения', tags: ['комедия', 'приключения', 'лёгкое'], description: 'Стильная, быстрая и очень уютная авантюра.'),
  MovieSuggestion(title: 'Назад в будущее', year: 1985, genre: 'фантастика / комедия', tags: ['фантастика', 'комедия', 'лёгкое'], description: 'Идеальный фильм для лёгкого вечера.'),
  MovieSuggestion(title: 'Достать ножи', year: 2019, genre: 'детектив / комедия', tags: ['детектив', 'комедия'], description: 'Умный детектив с отличным ансамблем.'),
  MovieSuggestion(title: 'Интерстеллар', year: 2014, genre: 'фантастика / драма', tags: ['фантастика', 'драма'], description: 'Большая эмоциональная история о времени и семье.'),
  MovieSuggestion(title: 'Начало', year: 2010, genre: 'фантастика / триллер', tags: ['фантастика', 'триллер'], description: 'Интеллектуальный триллер о снах и выборе.'),
  MovieSuggestion(title: 'Паразиты', year: 2019, genre: 'триллер / драма', tags: ['триллер', 'драма'], description: 'Напряжённая социальная история с неожиданными поворотами.'),
  MovieSuggestion(title: 'Семь', year: 1995, genre: 'триллер / детектив', tags: ['триллер', 'детектив'], description: 'Мрачный классический детектив.'),
  MovieSuggestion(title: 'Грань будущего', year: 2014, genre: 'фантастика / боевик', tags: ['фантастика', 'боевик'], description: 'Динамичный боевик с петлёй времени.'),
  MovieSuggestion(title: 'Безумный Макс: Дорога ярости', year: 2015, genre: 'боевик / приключения', tags: ['боевик', 'приключения'], description: 'Энергичный визуальный аттракцион без провисаний.'),
  MovieSuggestion(title: 'Дьявол носит Prada', year: 2006, genre: 'комедия / драма', tags: ['комедия', 'драма', 'лёгкое'], description: 'Лёгкая история о работе, границах и амбициях.'),
  MovieSuggestion(title: 'Амели', year: 2001, genre: 'романтика / комедия', tags: ['романтика', 'комедия', 'лёгкое'], description: 'Уютная романтическая сказка с французским настроением.'),
  MovieSuggestion(title: 'Ла-Ла Ленд', year: 2016, genre: 'романтика / драма', tags: ['романтика', 'драма'], description: 'Музыкальная история любви и несбывшихся планов.'),
  MovieSuggestion(title: 'Корпорация монстров', year: 2001, genre: 'мультфильм / комедия', tags: ['мультфильм', 'комедия', 'семейное'], description: 'Добрый семейный мультфильм на любой вечер.'),
  MovieSuggestion(title: 'Как приручить дракона', year: 2010, genre: 'мультфильм / приключения', tags: ['мультфильм', 'приключения', 'семейное'], description: 'Большое приключение с сердцем и отличной музыкой.'),
  MovieSuggestion(title: 'Остров проклятых', year: 2010, genre: 'триллер / детектив', tags: ['триллер', 'детектив', 'драма'], description: 'Атмосферный психологический детектив.'),
  MovieSuggestion(title: 'Зелёная книга', year: 2018, genre: 'драма / комедия', tags: ['драма', 'комедия'], description: 'Дорожная история о дружбе и предубеждениях.'),
  MovieSuggestion(title: 'Дюна', year: 2021, genre: 'фантастика / приключения', tags: ['фантастика', 'приключения', 'драма'], description: 'Масштабная фантастика с сильным миром.'),
  MovieSuggestion(title: 'Тихое место', year: 2018, genre: 'ужасы / триллер', tags: ['ужасы', 'триллер'], description: 'Напряжённый хоррор, где звук становится главным врагом.'),
  MovieSuggestion(title: 'Заклятие', year: 2013, genre: 'ужасы', tags: ['ужасы'], description: 'Классический атмосферный хоррор на ночь.'),
];
