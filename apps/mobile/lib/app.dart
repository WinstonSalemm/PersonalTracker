import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:personal_tracker_domain/domain.dart';
import 'package:personal_tracker_api_client/api_client.dart';
import 'package:personal_tracker_command_parser/command_parser.dart';
import 'package:personal_tracker_capture_v2/capture_v2.dart';
import 'package:personal_tracker_local_storage/local_storage.dart';
import 'package:personal_tracker_local_storage/web_backup_importer.dart';
import 'package:personal_tracker_english_roadmap/english_roadmap.dart';
import 'package:personal_tracker_english_roadmap/english_onboarding.dart';
import 'package:personal_tracker_sport_roadmap/sport_roadmap.dart';

import 'providers.dart';
import 'assistant_media.dart';
import 'sport_intake.dart';
import 'beta_auth.dart';

const _aiModels = <Map<String, String>>[
  {'id': 'gpt-4o-mini', 'label': 'Быстрая'},
  {'id': 'gpt-4o', 'label': 'Универсальная'},
  {'id': 'gpt-5', 'label': 'Точная'},
];

// Codev-Tim / Codev ERP tokens. The palette is intentionally global and
// mutable so the whole desktop surface can switch without changing any
// storage or domain contracts.
class _Palette {
  const _Palette({
    required this.base,
    required this.recessed,
    required this.surface,
    required this.elevated,
    required this.overlay,
    required this.amber,
    required this.amberHover,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.green,
    required this.red,
    required this.line,
    required this.lineStrong,
    required this.amberLine,
  });

  final Color base;
  final Color recessed;
  final Color surface;
  final Color elevated;
  final Color overlay;
  final Color amber;
  final Color amberHover;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color green;
  final Color red;
  final Color line;
  final Color lineStrong;
  final Color amberLine;
}

const _darkPalette = _Palette(
  base: Color(0xFF000000),
  recessed: Color(0xFF080808),
  surface: Color(0xFF0A0A0A),
  elevated: Color(0xFF000000),
  overlay: Color(0xFF000000),
  amber: Color(0xFFF0B429),
  amberHover: Color(0xFFF5C84D),
  primary: Color(0xFFEDEFF2),
  secondary: Color(0xFFA0A6B0),
  tertiary: Color(0xFF827967),
  green: Color(0xFFF0B429),
  red: Color(0xFFF0B429),
  line: Color(0x1AFFFFFF),
  lineStrong: Color(0x2EFFFFFF),
  amberLine: Color(0x40F0B429),
);

const _lightPalette = _Palette(
  base: Color(0xFFF5F5F3),
  recessed: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  elevated: Color(0xFFF0F0EE),
  overlay: Color(0xFFFAFAF8),
  amber: Color(0xFFC98500),
  amberHover: Color(0xFFA86300),
  primary: Color(0xFF12151C),
  secondary: Color(0xFF3D4654),
  tertiary: Color(0xFF7D766A),
  green: Color(0xFFC98500),
  red: Color(0xFFC98500),
  line: Color(0x1412151C),
  lineStrong: Color(0x2812151C),
  amberLine: Color(0x40C98500),
);

Color _base = _darkPalette.base;
Color _recessed = _darkPalette.recessed;
Color _surface = _darkPalette.surface;
Color _elevated = _darkPalette.elevated;
Color _overlay = _darkPalette.overlay;
Color _amber = _darkPalette.amber;
Color _amberHover = _darkPalette.amberHover;
Color _primary = _darkPalette.primary;
Color _secondary = _darkPalette.secondary;
Color _tertiary = _darkPalette.tertiary;
Color _green = _darkPalette.green;
Color _red = _darkPalette.red;
Color _line = _darkPalette.line;
Color _lineStrong = _darkPalette.lineStrong;
Color _amberLine = _darkPalette.amberLine;

void _applyPalette(bool light) {
  final palette = light ? _lightPalette : _darkPalette;
  _base = palette.base;
  _recessed = palette.recessed;
  _surface = palette.surface;
  _elevated = palette.elevated;
  _overlay = palette.overlay;
  _amber = palette.amber;
  _amberHover = palette.amberHover;
  _primary = palette.primary;
  _secondary = palette.secondary;
  _tertiary = palette.tertiary;
  _green = palette.green;
  _red = palette.red;
  _line = palette.line;
  _lineStrong = palette.lineStrong;
  _amberLine = palette.amberLine;
}

class AssistantApp extends StatefulWidget {
  const AssistantApp({super.key});

  @override
  State<AssistantApp> createState() => _AssistantAppState();
}

class _AssistantAppState extends State<AssistantApp> {
  // Follow the OS on launch; the in-app toggle can still override it for the
  // current run without persisting a surprising theme choice.
  bool _light = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.light;

  @override
  void initState() {
    super.initState();
    _applyPalette(_light);
  }

  void _toggleTheme() => setState(() {
        _light = !_light;
        _applyPalette(_light);
      });

  @override
  Widget build(BuildContext context) {
    final baseTheme = _light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: _amber,
      brightness: _light ? Brightness.light : Brightness.dark,
    ).copyWith(
      primary: _amber,
      onPrimary: _base,
      secondary: _amberHover,
      onSecondary: _base,
      surface: _surface,
      onSurface: _primary,
      onSurfaceVariant: _secondary,
      outline: _lineStrong,
      error: _red,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Codev Assistant',
      theme: baseTheme.copyWith(
        brightness: _light ? Brightness.light : Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: _base,
        canvasColor: _base,
        textTheme: baseTheme.textTheme.apply(
          bodyColor: _primary,
          displayColor: _primary,
          fontFamily: 'Bahnschrift',
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: _base,
          foregroundColor: _primary,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.transparent,
          hintStyle: TextStyle(color: _tertiary),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _amber, width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _amber,
            foregroundColor: _base,
            disabledBackgroundColor: _elevated,
            disabledForegroundColor: _tertiary,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            textStyle: TextStyle(fontWeight: FontWeight.w700),
          ).copyWith(
            mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _primary,
            side: BorderSide(color: _lineStrong),
            minimumSize: const Size(0, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ).copyWith(
            mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: _recessed,
          indicatorColor: _amber.withAlpha(35),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected) ? _amber : _tertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      builder: (context, child) => child ?? const SizedBox.shrink(),
      home: Consumer(
        builder: (context, ref, _) => BetaSessionGate(
          manager: ref.watch(authManagerProvider),
          builder: (context, session) => AssistantHome(
            isLight: _light,
            onToggleTheme: _toggleTheme,
            session: session,
          ),
        ),
      ),
    );
  }
}

enum _SportPlanProposalKind { recoveryOnce, injuryPause }

class _SportPlanProposal {
  const _SportPlanProposal._(this.kind, this.reply, this.appliedReply,
      {this.resource});
  const _SportPlanProposal.run()
      : this._(
          _SportPlanProposalKind.recoveryOnce,
          'Внеплановая пробежка может добавить нагрузку на ноги. Предлагаю заменить ближайшую силовую на восстановление и mobility на 25–35 минут. Очередь A/B/C/D не сдвинется. Применить?',
          'Готово: ближайшая силовая заменена на одну восстановительную сессию. После неё вернёмся к той же A/B/C/D очереди.',
        );
  _SportPlanProposal.injuryFor(String details)
      : this._(
          _SportPlanProposalKind.injuryPause,
          'Похоже, есть травма или боль: $details. Я не ставлю диагнозов. Предлагаю поставить силовые на паузу и переключить будущие тренировки на «Возвращение к нагрузке». Ниже будет справочный материал профильной организации — это не назначение. При сильной боли, отёке, деформации, онемении или невозможности опоры обратитесь за медицинской помощью. Применить?',
          'Готово: силовые поставлены на паузу, а будущий план переключён на щадящее «Возвращение к нагрузке». Возобновление — только вручную, когда это безопасно для вас.',
          resource: _injuryResource(details),
        );

  final _SportPlanProposalKind kind;
  final String reply;
  final String appliedReply;
  final _InjuryResource? resource;

  static _InjuryResource _injuryResource(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('колен'))
      return const _InjuryResource('Колено: AAOS Knee Conditioning Program',
          'https://orthoinfo.aaos.org/globalassets/pdfs/2017-rehab_knee.pdf');
    if (lower.contains('плеч'))
      return const _InjuryResource('Плечо: AAOS Shoulder Conditioning Program',
          'https://orthoinfo.aaos.org/en/recovery/rotator-cuff-and-shoulder-conditioning-program');
    if (lower.contains('спин') || lower.contains('поясниц'))
      return const _InjuryResource('Спина: NHS physiotherapy and exercises',
          'https://www.guysandstthomas.nhs.uk/health-information/low-back-pain/physiotherapy-and-exercises');
    return const _InjuryResource('Голеностоп: NHS ankle sprain guidance',
        'https://www.pah.nhs.uk/resources/ankle-sprain/');
  }
}

class _InjuryResource {
  const _InjuryResource(this.title, this.url);
  final String title;
  final String url;
}

class AssistantHome extends ConsumerStatefulWidget {
  const AssistantHome({
    super.key,
    required this.isLight,
    required this.onToggleTheme,
    required this.session,
  });

  final bool isLight;
  final VoidCallback onToggleTheme;
  final BetaSession session;

  @override
  ConsumerState<AssistantHome> createState() => _AssistantHomeState();
}

class _AssistantDockGeometry {
  const _AssistantDockGeometry({required this.position, required this.size});

  final Offset position;
  final Size size;
}

class _AssistantHomeState extends ConsumerState<AssistantHome>
    with WidgetsBindingObserver {
  static const _forceWorkspaceSetup =
      bool.fromEnvironment('PT_FORCE_ONBOARDING');
  int _tab = 0;
  final _text = TextEditingController();
  final _composerFocus = FocusNode(debugLabel: 'assistant-chat-composer');
  final _assistantText = TextEditingController();
  final _speech = SpeechToText();
  CaptureDraft? _draft;
  CaptureEnvelopeV2? _canonicalMoneyDraft;
  AssistantPlan? _assistantPlan;
  bool _listening = false;
  bool _busy = false;
  bool _assistantBusy = false;
  bool _startupSyncStarted = false;
  String? _notice;
  String? _assistantNotice;
  final _chatMessages = <Map<String, dynamic>>[];
  final _chatAttachments = <PlatformFile>[];
  String? _chatConversationId;
  String? _chatMemoryCandidateId;
  _SportPlanProposal? _sportPlanProposal;
  bool _awaitingInjuryDetails = false;
  String? _chatError;
  bool _chatBusy = false;
  String _selectedAiModel = 'gpt-5';
  bool _workspaceLoaded = false;
  bool _showWorkspaceSetup = false;
  Timer? _syncRetryTimer;
  bool _syncInFlight = false;
  bool _appActive = true;
  bool _canonicalSyncRepairAvailable = false;
  CaptureRollout _captureRollout = const CaptureRollout.disabled();
  DateTime? _captureRolloutFetchedAt;
  static const _captureRolloutCacheTtl = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_appActive) unawaited(_retryPendingSync());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) unawaited(_retryPendingSync());
  }

  Future<void> _retryPendingSync() async {
    if (_syncInFlight || !mounted) return;
    _syncInFlight = true;
    try {
      final database = await ref.read(databaseProvider.future);
      await _syncPending(database);
      await _syncCanonicalPending(database);
    } catch (_) {
      // Keep the outbox intact; the next timer/foreground event retries it.
    } finally {
      _syncInFlight = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _syncCanonicalPending(LocalDatabase database) async {
    final pending = database.pendingCanonicalMoneySync();
    if (pending.isEmpty) return;
    final synced = <String>[];
    var permanentFailure = false;
    for (final row in pending) {
      final captureId = row['capture_id'] as String;
      database.markCanonicalMoneySending(captureId);
      final intentEnvelope = jsonDecode(row['intent_json'] as String) as Map;
      final intent = Map<String, dynamic>.from(
          (intentEnvelope['intent'] as Map).cast<String, dynamic>());
      try {
        await ref.read(apiProvider).commitCanonicalMoney({
          'captureId': captureId,
          'exactMinorUnits': row['exact_minor_units'],
          'currency': row['currency'],
          'direction': row['type'],
          'date': row['date'],
          'description': row['purpose'],
          'accountId': row['account_id'],
          'categoryId': row['category_id'],
          'paymentMethod': row['payment_method'],
          'schemaVersion': 2,
          'intent': intent,
        });
        synced.add(captureId);
        _reportCaptureRolloutMetric('v2_money_sync_acknowledged');
      } on CanonicalCommitException catch (error) {
        if (error.retryable) {
          database.markCanonicalMoneyRetryableFailure(
            captureId,
            errorCode: error.code,
          );
        } else {
          database.markCanonicalMoneyPermanentFailure(
            captureId,
            errorCode: error.code,
          );
        }
        _reportCaptureRolloutMetric(error.retryable
            ? 'v2_money_sync_retryable_failure'
            : 'v2_money_sync_permanent_failure');
        permanentFailure = !error.retryable;
        if (!error.retryable) _canonicalSyncRepairAvailable = true;
        if (error.retryable) rethrow;
      }
    }
    await database.markCanonicalMoneySynced(synced);
    if (permanentFailure && mounted) {
      setState(() => _notice =
          'Сохранено на устройстве, но синхронизация требует внимания. Исправьте данные и повторите.');
    }
  }

  Future<void> _repairCanonicalMoneySync() async {
    final database = await ref.read(databaseProvider.future);
    final requeued = database.requeueCanonicalMoneyFailures();
    if (!mounted) return;
    setState(() {
      _canonicalSyncRepairAvailable = false;
      _notice = requeued == 0
          ? 'Нет записей, которые нужно повторить.'
          : 'Повтор синхронизации поставлен в очередь. Дубликат не будет создан.';
    });
    unawaited(_retryPendingSync());
  }

  bool _workspaceSetupCompleted = false;
  bool _assistantDockOpen = false;
  bool _assistantDockMinimized = false;
  final _assistantDockGeometry = ValueNotifier<_AssistantDockGeometry?>(null);
  Set<String> _enabledModules = const {};
  Map<String, dynamic> _languageProfile = const {
    'targetLanguage': 'Английский',
    'goal': 'Свободно общаться',
    'currentLevel': 'Начинаю с нуля',
    'weeks': 12,
  };

  static const _availableModules = <_WorkspaceModule>[
    _WorkspaceModule(
      id: 'languages',
      shortLabel: 'Языки',
      label: 'Языковой курс',
      description: 'Персональный roadmap, практика и прогресс',
      icon: Icons.translate_rounded,
    ),
    _WorkspaceModule(
      id: 'money',
      shortLabel: 'Деньги',
      label: 'Деньги',
      description: 'Остатки, расходы, обязательства и понятная аналитика',
      icon: Icons.account_balance_wallet_outlined,
    ),
    _WorkspaceModule(
      id: 'sport',
      shortLabel: 'Спорт',
      label: 'Тренировки',
      description: 'Безопасный план, история и прогресс нагрузок',
      icon: Icons.fitness_center_outlined,
    ),
    _WorkspaceModule(
      id: 'sales',
      shortLabel: 'Продажи',
      label: 'Продажи для работы',
      description: 'Для тех, кто ведёт клиентов, звонки и следующие шаги',
      icon: Icons.phone_in_talk_outlined,
    ),
  ];

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncRetryTimer?.cancel();
    _text.dispose();
    _composerFocus.dispose();
    _assistantText.dispose();
    _assistantDockGeometry.dispose();
    super.dispose();
  }

  Future<void> _parseAssistant() async {
    if (_assistantText.text.trim().isEmpty) {
      setState(() => _assistantNotice =
          'Напишите, что нужно сделать, или используйте пример.');
      return;
    }
    setState(() {
      _assistantBusy = true;
      _assistantNotice = null;
      _assistantPlan = null;
    });
    final parsed =
        await DeterministicAssistantParser().parse(_assistantText.text);
    var plan =
        parsed == null ? null : await AssistantImageResolver().enrich(parsed);
    if (plan != null) plan = await _resolveAssistantContact(plan);
    if (!mounted) return;
    if (plan != null && _shouldAutoExecute(plan)) {
      setState(() {
        _assistantPlan = plan;
        _assistantBusy = false;
      });
      unawaited(_retryPendingSync());
      await _executeAssistant();
      return;
    }
    setState(() {
      _assistantPlan = plan;
      _assistantBusy = false;
      _assistantNotice = plan == null
          ? 'Пока не понял запрос. Попробуйте: «5 комедий на вечер», «поставь задачу купить молоко завтра в 19:00», «позвони +998…» или «напиши @username в Telegram …».'
          : null;
    });
  }

  bool _shouldAutoExecute(AssistantPlan plan) {
    if (plan.intent == AssistantIntent.task ||
        plan.intent == AssistantIntent.contact) return true;
    if (plan.intent == AssistantIntent.call ||
        plan.intent == AssistantIntent.telegram) {
      return plan.hasTarget;
    }
    return false;
  }

  Future<AssistantPlan> _resolveAssistantContact(AssistantPlan plan) async {
    if (plan.intent != AssistantIntent.call &&
        plan.intent != AssistantIntent.telegram) {
      return plan;
    }
    if (plan.hasTarget || plan.contactName == null) return plan;
    final database = await ref.read(databaseProvider.future);
    final contact = database.assistantContactByName(plan.contactName!);
    if (contact == null) return plan;
    return plan.copyWith(
      contactName: contact.name,
      phone: contact.phone,
      telegramUsername: contact.telegramUsername,
    );
  }

  Future<void> _executeAssistant() async {
    final plan = _assistantPlan;
    if (plan == null) return;
    setState(() {
      _assistantBusy = true;
      _assistantNotice = null;
    });
    try {
      switch (plan.intent) {
        case AssistantIntent.movies:
          _assistantNotice =
              'Подборка готова — можно выбрать фильм из списка ниже.';
        case AssistantIntent.visual:
          _assistantNotice =
              'Изображение готово — можно рассмотреть результат ниже.';
        case AssistantIntent.task:
          final task = AssistantTask(
            id: _id(),
            title: plan.taskTitle ?? 'Новая задача',
            originalText: plan.originalText,
            dueAt: plan.dueAt,
            createdAt: DateTime.now(),
          );
          final database = await ref.read(databaseProvider.future);
          await database.saveAssistantTask(task);
          final opened = await _openCalendar(task);
          _assistantNotice = opened
              ? 'Задача сохранена локально. Открыл шаблон календаря — нажмите «Сохранить».'
              : 'Задача сохранена локально. Календарь не открылся автоматически.';
        case AssistantIntent.contact:
          final name = plan.contactName;
          if (name == null || name.isEmpty) {
            throw StateError(
                'Не понял имя контакта. Пример: «запомни контакт мама +998 90 123 45 67».');
          }
          final database = await ref.read(databaseProvider.future);
          await database.saveAssistantContact(
            AssistantContact(
              id: _id(),
              name: name,
              phone: plan.phone,
              telegramUsername: plan.telegramUsername,
              createdAt: DateTime.now(),
            ),
          );
          _assistantNotice =
              'Контакт «$name» сохранён. Теперь можно сказать «позвони $name» или «напиши $name в Telegram».';
        case AssistantIntent.call:
          final phone = plan.phone;
          if (phone == null) {
            throw StateError(
                'Контакт «${plan.contactName ?? 'без имени'}» не найден. Сначала запомните его номер.');
          }
          final opened = await launchUrl(
            Uri(scheme: 'tel', path: phone),
            mode: LaunchMode.externalApplication,
          );
          if (!opened)
            throw StateError('Системное приложение телефона недоступно.');
          _assistantNotice =
              'Открываю звонок${plan.contactName == null ? '' : ' для ${plan.contactName}'}.';
        case AssistantIntent.telegram:
          final opened = await _openTelegram(plan);
          if (!opened)
            throw StateError('Telegram не установлен и ссылка не открылась.');
          _assistantNotice = 'Открываю Telegram с подготовленным сообщением.';
      }
      if (mounted) {
        setState(() {
          _assistantBusy = false;
          _assistantPlan = null;
          _assistantText.clear();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _assistantBusy = false;
          _assistantNotice = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  Future<bool> _openCalendar(AssistantTask task) async {
    final query = <String, String>{
      'action': 'TEMPLATE',
      'text': task.title,
      'details': task.originalText,
    };
    if (task.dueAt != null) {
      final start = task.dueAt!;
      final end = start.add(const Duration(hours: 1));
      query['dates'] = '${_calendarStamp(start)}/${_calendarStamp(end)}';
    }
    return launchUrl(
      Uri.https('calendar.google.com', '/calendar/render', query),
      mode: LaunchMode.externalApplication,
    );
  }

  String _calendarStamp(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}T${value.hour.toString().padLeft(2, '0')}${value.minute.toString().padLeft(2, '0')}00';

  Future<bool> _openTelegram(AssistantPlan plan) async {
    final message = Uri.encodeComponent(plan.message ?? '');
    final target = plan.telegramUsername == null
        ? 'phone=${Uri.encodeComponent(plan.phone ?? '')}'
        : 'domain=${Uri.encodeComponent(plan.telegramUsername!)}';
    final deepLink = Uri.parse('tg://resolve?$target&text=$message');
    if (await launchUrl(deepLink, mode: LaunchMode.externalApplication))
      return true;
    if (plan.telegramUsername == null) return false;
    return launchUrl(
      Uri.https(
          't.me', '/${plan.telegramUsername}', {'text': plan.message ?? ''}),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _completeAssistantTask(String id) async {
    final database = await ref.read(databaseProvider.future);
    await database.completeAssistantTask(id);
    if (mounted) setState(() {});
  }

  Future<void> _parse() async {
    final rawInput = _text.text.trim();
    if (rawInput.isEmpty) {
      setState(() => _notice = 'Введите команду или используйте микрофон.');
      return;
    }
    // Canonical Money gets one V2-owned review. It deliberately runs before
    // V1 so a V1-unsupported income can still be explicitly confirmed, while
    // feature-off preserves the existing V1 path byte-for-byte.
    final rollout = await _captureRolloutForNewCaptures();
    if (rollout.captureMoneyV2 &&
        await _prepareCanonicalMoneyReview(rawInput)) {
      return;
    }
    // Shadow observes an explicit user submission, independently from V1
    // recognition and review/save. It is intentionally detached: failure to
    // open storage or parse V2 cannot alter V1 preview, input, or Save.
    if (rollout.captureCoreV2Shadow) {
      unawaited(_observeV2ShadowSubmission(rawInput));
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final draft = await ref.read(commandParserProvider).parse(rawInput);
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _busy = false;
      _notice = draft == null
          ? 'Не удалось распознать команду. Уточните текст.'
          : null;
    });
  }

  Future<CaptureRollout> _captureRolloutForNewCaptures() async {
    if (!CaptureV2FeatureFlags.remoteRolloutEnabled) {
      return CaptureRollout(
        captureCoreV2Shadow: CaptureV2FeatureFlags.captureCoreV2Shadow,
        captureMoneyV2: CaptureV2FeatureFlags.captureMoneyV2,
        fetchedAt: null,
      );
    }
    final fetchedAt = _captureRolloutFetchedAt;
    if (fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _captureRolloutCacheTtl) {
      return _captureRollout;
    }
    try {
      final rollout = await ref.read(apiProvider).fetchCaptureRollout();
      if (!mounted) return const CaptureRollout.disabled();
      _captureRollout = rollout;
      _captureRolloutFetchedAt = DateTime.now();
      return rollout;
    } catch (_) {
      // Fail closed for new captures. Existing canonical outbox rows continue
      // through _syncCanonicalPending so a rollback cannot strand them.
      return const CaptureRollout.disabled();
    }
  }

  void _reportCaptureRolloutMetric(String event) {
    unawaited(() async {
      try {
        await ref.read(apiProvider).reportCaptureRolloutMetric(event);
      } catch (_) {
        // Telemetry is deliberately best effort and contains no raw capture.
      }
    }());
  }

  Future<bool> _prepareCanonicalMoneyReview(String rawInput) async {
    setState(() {
      _busy = true;
      _notice = null;
      _draft = null;
      _canonicalMoneyDraft = null;
    });
    try {
      final database = await ref.read(databaseProvider.future);
      final result = await CaptureV2ShadowRunner(
        adapter: V1ParserToV2Adapter(ref.read(commandParserProvider)),
        database: database,
        enabled: true,
      ).run(rawInput);
      final envelope = result?.envelope;
      final intent = envelope?.intent;
      final eligible = envelope != null &&
          intent is MoneyIntentV2 &&
          !envelope.isUnsupported &&
          !envelope.unresolved.any((item) => item.risk == 'high');
      if (!mounted) return false;
      if (eligible) {
        setState(() {
          _canonicalMoneyDraft = envelope;
          _busy = false;
        });
        _reportCaptureRolloutMetric('v2_money_review_opened');
        return true;
      }
    } catch (_) {
      // Canonical diagnostics/review must never prevent the legacy V1 path.
    }
    if (mounted) setState(() => _busy = false);
    return false;
  }

  Future<void> _confirmCanonicalMoney() async {
    final draft = _canonicalMoneyDraft;
    if (draft == null || _busy) return;
    final suggested = _applyMoneySuggestions(draft);
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await CanonicalMoneyCommitService(await ref.read(databaseProvider.future),
              enabled: true)
          .confirm(suggested.withReviewState(V2ReviewState.reviewed));
      _reportCaptureRolloutMetric('v2_money_committed_local');
      if (!mounted) return;
      setState(() {
        _canonicalMoneyDraft = null;
        _text.clear();
        _busy = false;
        _notice =
            'Сохранено локально в Money. Синхронизация будет добавлена отдельно.';
      });
      unawaited(_retryPendingSync());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice =
            'Не удалось сохранить запись. Проверьте данные и повторите попытку.';
      });
    }
  }

  CaptureEnvelopeV2 _applyMoneySuggestions(CaptureEnvelopeV2 envelope) {
    final lower = envelope.originalText.toLowerCase();
    final salary = RegExp(r'зарплат|зп|salary|maosh|ойлик').hasMatch(lower);
    final card = salary || RegExp(r'карт|карта|card|bank card').hasMatch(lower);
    return envelope.withMoneyEdits(
      account: card ? 'card-main' : null,
      category: salary ? 'salary' : null,
    );
  }

  Future<void> _editCanonicalMoney() async {
    final envelope = _canonicalMoneyDraft;
    if (envelope == null || envelope.intent is! MoneyIntentV2) return;
    final intent = envelope.intent as MoneyIntentV2;
    final database = await ref.read(databaseProvider.future);
    final accounts = database.moneyAccounts();
    final categories = database
        .moneyCategories()
        .where((item) =>
            item.kind ==
            (intent.direction == MoneyDirectionV2.income
                ? MoneyCategoryKind.income
                : MoneyCategoryKind.expense))
        .toList();
    final salaryHint =
        RegExp(r'зарплат|зп|salary|maosh|ойлик', caseSensitive: false)
            .hasMatch(envelope.originalText);
    final cardHint = salaryHint ||
        RegExp(r'карт|карта|card|bank card', caseSensitive: false)
            .hasMatch(envelope.originalText);
    final result = await showDialog<(String?, String?)>(
      context: context,
      builder: (context) {
        var account = intent.account == 'unassigned'
            ? (cardHint ? 'card-main' : null)
            : intent.account;
        var category = intent.category == 'unclassified'
            ? (salaryHint ? 'salary' : null)
            : intent.category;
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Быстро изменить Money'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              if (salaryHint || cardHint)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Предположение — проверьте перед сохранением: '
                    '${cardHint ? 'карта' : ''}${salaryHint ? ' · зарплата' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              DropdownButtonFormField<String?>(
                value: account,
                decoration: const InputDecoration(labelText: 'Счёт'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Не указан')),
                  ...accounts.map((item) => DropdownMenuItem<String?>(
                      value: item.id, child: Text(item.name))),
                ],
                onChanged: (value) => setDialogState(() => account = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: category,
                decoration: const InputDecoration(labelText: 'Категория'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Не классифицировано')),
                  ...categories.map((item) => DropdownMenuItem<String?>(
                      value: item.id, child: Text(item.name))),
                ],
                onChanged: (value) => setDialogState(() => category = value),
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, (account, category)),
                  child: const Text('Применить')),
            ],
          );
        });
      },
    );
    if (!mounted || result == null) return;
    final edited = envelope.withMoneyEdits(
      account: result.$1 ?? 'unassigned',
      category: result.$2 ?? 'unclassified',
    );
    if (edited.intent is MoneyIntentV2 && envelope.intent is MoneyIntentV2) {
      final before = envelope.intent as MoneyIntentV2;
      final after = edited.intent as MoneyIntentV2;
      if (before.account != after.account || before.category != after.category) {
        _reportCaptureRolloutMetric('v2_money_review_edited');
      }
    }
    setState(() {
      _canonicalMoneyDraft = edited;
    });
  }

  void _cancelCanonicalMoneyReview() {
    _reportCaptureRolloutMetric('v2_money_review_cancelled');
    setState(() {
      _canonicalMoneyDraft = null;
      _text.clear();
    });
  }

  Future<void> _observeV2ShadowSubmission(String rawInput) async {
    try {
      final database = await ref.read(databaseProvider.future);
      await CaptureV2ShadowRunner(
        adapter: V1ParserToV2Adapter(ref.read(commandParserProvider)),
        database: database,
      ).run(rawInput);
    } catch (_) {
      // The capture UI has no shadow error state by design. Runner diagnostics
      // are retained locally where persistence is available.
    }
  }

  String _sanitizeChatMessage(String raw) {
    final normalizedLines = raw.replaceAll('\r\n', '\n').split('\n');
    final result = <String>[];
    var emptyLines = 0;

    for (final rawLine in normalizedLines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        emptyLines += 1;
        if (emptyLines > 3) break;
        result.add('');
      } else {
        emptyLines = 0;
        result.add(line);
      }
    }

    while (result.isNotEmpty && result.first.isEmpty) {
      result.removeAt(0);
    }
    while (result.isNotEmpty && result.last.isEmpty) {
      result.removeLast();
    }
    return result.join('\n');
  }

  Future<void> _sendAssistantMessage() async {
    final message = _sanitizeChatMessage(_assistantText.text);
    final attachments = List<PlatformFile>.from(_chatAttachments);
    if (message.isEmpty && attachments.isEmpty) {
      setState(() => _chatError = 'Напишите сообщение или выберите пример.');
      return;
    }
    final requestMessage = message.isEmpty
        ? 'User attached ${attachments.length} photo(s).'
        : message;
    setState(() {
      _chatBusy = true;
      _chatError = null;
      _notice = null;
      _chatMessages.add({
        'role': 'Вы',
        'text': message.isEmpty ? 'Фото прикреплено' : message,
        if (attachments.isNotEmpty) 'attachments': attachments,
      });
      _assistantText.clear();
      _chatAttachments.clear();
    });

    if (attachments.isNotEmpty) {
      setState(() {
        _chatBusy = false;
        _chatMessages.add({
          'role': 'AI',
          'text':
              'Фото прикреплено. Опишите, что нужно сделать с ним: визуальный анализ ещё не подключён к API.',
        });
      });
      if (message.isEmpty) return;
    }

    final wasAwaitingInjuryDetails = _awaitingInjuryDetails;
    final sportProposal = _sportProposalFor(requestMessage);
    if (wasAwaitingInjuryDetails && sportProposal == null) {
      _awaitingInjuryDetails = false;
      final followUp = _SportPlanProposal.injuryFor(requestMessage);
      setState(() {
        _chatBusy = false;
        _sportPlanProposal = followUp;
        _chatMessages.add({'role': 'AI', 'text': followUp.reply});
      });
      return;
    }
    if (_awaitingInjuryDetails && sportProposal == null) {
      setState(() {
        _chatBusy = false;
        _chatMessages.add({
          'role': 'AI',
          'text':
              'Чтобы подобрать только справочные материалы для аккуратного возвращения, уточните одним сообщением: какая часть тела и что произошло — например, «подвернул голеностоп» или «болит колено после бега». '
        });
      });
      return;
    }
    if (sportProposal != null) {
      setState(() {
        _chatBusy = false;
        _sportPlanProposal = sportProposal;
        _chatMessages.add({'role': 'AI', 'text': sportProposal.reply});
      });
      return;
    }

    final draft = await ref.read(commandParserProvider).parse(requestMessage);
    if (!mounted) return;
    if (draft != null) {
      setState(() {
        _draft = draft;
        _chatBusy = false;
        _chatMessages.add({
          'role': 'AI',
          'text':
              'Похоже на запись в разделе «${_captureDestination(draft.type)}». Проверьте карточку ниже: я сохраню её только после вашего подтверждения.'
        });
      });
      return;
    }

    try {
      final result = await ref
          .read(authManagerProvider)
          .authenticatedRequest('POST', '/api/ai/chat', body: {
        'message': requestMessage,
        'model': _selectedAiModel,
        if (_chatConversationId != null) 'conversationId': _chatConversationId,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _chatConversationId = result['conversationId'] as String?;
        _chatMemoryCandidateId = result['memoryCandidateId'] as String?;
        _chatMessages.add({
          'role': 'AI',
          'text': result['answer'] as String? ?? 'Не удалось получить ответ.'
        });
      });
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _chatError = error.userMessage);
    } finally {
      if (mounted) setState(() => _chatBusy = false);
    }
  }

  Future<void> _pickChatImages() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || !mounted) return;

    const maxFiles = 5;
    const maxFileBytes = 8 * 1024 * 1024;
    final availableSlots = maxFiles - _chatAttachments.length;
    final accepted = picked.files
        .where((file) => file.bytes != null && file.size <= maxFileBytes)
        .take(max(0, availableSlots))
        .toList(growable: false);
    final skipped = picked.files.length - accepted.length;
    setState(() {
      _chatAttachments.addAll(accepted);
      _chatError = skipped == 0
          ? null
          : 'Можно прикрепить до $maxFiles фото размером до 8 МБ каждое.';
    });
  }

  void _removeChatAttachment(PlatformFile file) =>
      setState(() => _chatAttachments.remove(file));

  _SportPlanProposal? _sportProposalFor(String message) {
    final value = message.toLowerCase();
    if (RegExp(r'травм|болит|боль|подвернул|растян|отек|перелом')
        .hasMatch(value)) {
      if (!RegExp(r'колен|плеч|голен|лодыж|щиколот|спин|поясниц')
          .hasMatch(value)) {
        _awaitingInjuryDetails = true;
        return null;
      }
      return _SportPlanProposal.injuryFor(message);
    }
    if (RegExp(r'пробеж|\bбег\b|бежал|бегал|\brun\b').hasMatch(value)) {
      return const _SportPlanProposal.run();
    }
    return null;
  }

  Future<void> _decideSportPlanProposal(bool approve) async {
    final proposal = _sportPlanProposal;
    if (proposal == null) return;
    if (!approve) {
      setState(() {
        _sportPlanProposal = null;
        _chatMessages.add({
          'role': 'AI',
          'text':
              'План не меняю. Событие можно записать отдельно, если захотите.'
        });
      });
      return;
    }
    final database = await ref.read(databaseProvider.future);
    final raw = database.sportTrainingProfileJson();
    if (raw == null) {
      setState(() {
        _sportPlanProposal = null;
        _chatError =
            'Сначала создайте спортивный профиль — тогда я смогу безопасно менять ваш план.';
      });
      return;
    }
    final profile =
        SportTrainingProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final updated = proposal.kind == _SportPlanProposalKind.injuryPause
        ? profile.copyWith(
            presetId: 'return-to-training', adaptation: 'injury-pause')
        : profile.copyWith(adaptation: 'recovery-once');
    await database.saveSportTrainingProfileJson(jsonEncode(updated.toJson()));
    if (!mounted) return;
    setState(() {
      _sportPlanProposal = null;
      _chatMessages.add({'role': 'AI', 'text': proposal.appliedReply});
    });
  }

  String _captureDestination(CaptureType type) => switch (type) {
        CaptureType.expense => 'Деньги',
        CaptureType.income => 'Деньги',
        CaptureType.salesCall => 'Продажи',
        CaptureType.english => 'Английский',
        CaptureType.sports => 'Тренировки',
      };

  Future<void> _decideChatMemory(bool approve) async {
    final id = _chatMemoryCandidateId;
    if (id == null) return;
    try {
      await ref.read(authManagerProvider).authenticatedRequest('POST',
          '/api/ai/memory/candidates/$id/${approve ? 'approve' : 'reject'}');
      if (!mounted) return;
      setState(() {
        _chatMemoryCandidateId = null;
        _chatMessages.add({
          'role': 'AI',
          'text': approve
              ? 'Готово, сохранено как подтверждённое предпочтение.'
              : 'Не сохраняю это в память.'
        });
      });
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _chatError = error.userMessage);
    }
  }

  Future<void> _listenInto({
    required TextEditingController controller,
    required Future<void> Function() onFinal,
    required bool assistant,
  }) async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ready = await _speech.initialize();
    if (!ready || !mounted) {
      if (mounted) {
        setState(() {
          if (assistant) {
            _chatError = 'Системное распознавание речи недоступно.';
          } else {
            _notice = 'Системное распознавание речи недоступно.';
          }
        });
      }
      return;
    }
    setState(() {
      _listening = true;
      if (assistant) {
        _chatError = null;
      } else {
        _notice = null;
      }
    });
    await _speech.listen(
      onResult: (result) {
        controller.text = result.recognizedWords;
        if (result.finalResult) {
          setState(() => _listening = false);
          unawaited(onFinal());
        }
      },
      listenOptions: SpeechListenOptions(localeId: 'ru_RU'),
    );
  }

  Future<void> _listenForCapture() => _listenInto(
        controller: _text,
        onFinal: _parse,
        assistant: false,
      );

  Future<void> _listenForAssistant() => _listenInto(
        controller: _assistantText,
        onFinal: _sendAssistantMessage,
        assistant: true,
      );

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    final database = await ref.read(databaseProvider.future);
    final record = CaptureRecord(
      id: _id(),
      draft: draft,
      createdAt: DateTime.now(),
    );
    await database.save(record);
    try {
      await _syncPending(database);
      _notice = 'Сохранено локально и синхронизировано';
    } catch (_) {
      _notice = 'Сохранено локально. Синхронизация повторится позже.';
    }
    if (mounted) {
      setState(() {
        _draft = null;
        _text.clear();
        _chatMessages.add({
          'role': 'AI',
          'text':
              'Готово, запись сохранена. Её можно посмотреть в нужном разделе и в записях за сегодня.'
        });
      });
      unawaited(_trackBetaEvent('confirmed_record_saved', database: database));
    }
  }

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  Future<void> _syncPending(LocalDatabase database) async {
    final pending = database.pending();
    if (pending.isEmpty) return;
    await ref.read(apiProvider).sync(pending);
    await database.markSynced(pending.map((item) => item.id));
  }

  Future<void> _importWebBackup() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;
    final database = await ref.read(databaseProvider.future);
    try {
      final value = jsonDecode(utf8.decode(picked.files.single.bytes!));
      if (value is! Map) throw const FormatException('not_object');
      final report = await WebBackupImporter.importInto(
        database,
        Map<String, dynamic>.from(value),
      );
      if (!mounted) return;
      setState(() => _notice =
          'Backup: найдено ${report.found}, импортировано ${report.imported}, пропущено ${report.skipped}. ${report.warnings.join(' ')}');
    } catch (_) {
      if (mounted) {
        setState(() => _notice =
            'Не удалось прочитать резервную копию JSON. Исходный файл не изменён.');
      }
    }
  }

  List<_WorkspaceModule> get _visibleModules => _availableModules
      .where((module) => _enabledModules.contains(module.id))
      .toList(growable: false);

  List<_Destination> get _destinations => [
        const _Destination(
          'home',
          'Главная',
          'Сегодня',
          Icons.bolt_rounded,
        ),
        ..._visibleModules.map(
          (module) => _Destination(
            module.id,
            module.shortLabel,
            module.label,
            module.icon,
          ),
        ),
        const _Destination(
          'account',
          'Аккаунт',
          'Аккаунт',
          Icons.person_outline_rounded,
        ),
      ];

  void _ensureWorkspaceLoaded(LocalDatabase database) {
    if (_workspaceLoaded) return;
    _workspaceLoaded = true;
    unawaited(_trackBetaEvent('app_open', database: database));
    final savedModules = database.preference('workspace.modules');
    if (savedModules is List) {
      final allowed = _availableModules.map((module) => module.id).toSet();
      _enabledModules =
          savedModules.whereType<String>().where(allowed.contains).toSet();
    } else if (database.hasMeaningfulUserData()) {
      // Existing installations keep every legacy workspace visible until the
      // owner explicitly customizes it. Fresh installs start with a real
      // choice instead of four preselected products.
      _enabledModules = _availableModules.map((module) => module.id).toSet();
    }
    final savedLanguage = database.preference('language.profile');
    if (savedLanguage is Map) {
      _languageProfile = Map<String, dynamic>.from(savedLanguage);
    }
    final setupCompleted = database.preference('workspace.setupCompleted');
    _workspaceSetupCompleted =
        setupCompleted == true || database.hasMeaningfulUserData();
    _showWorkspaceSetup = _forceWorkspaceSetup || !_workspaceSetupCompleted;
  }

  Future<void> _saveWorkspaceSetup(
    LocalDatabase database,
    _WorkspaceSetupResult result,
  ) async {
    await database.savePreference(
      'workspace.modules',
      result.enabledModules.toList()..sort(),
    );
    await database.savePreference('language.profile', result.languageProfile);
    await database.savePreference('workspace.setupCompleted', true);
    if (result.enabledModules.contains('money')) {
      final accounts = database.moneyAccounts();
      for (final account in accounts) {
        final isCash = account.id == 'cash-main';
        final isCard = account.id == 'card-main';
        if (!isCash && !isCard) continue;
        await database.saveMoneyAccount(
          MoneyAccount(
            id: account.id,
            name: isCash ? result.cashName : result.cardName,
            type: account.type,
            currency: result.currency,
            initialBalance: isCash ? result.cashBalance : result.cardBalance,
            color: account.color,
            createdAt: account.createdAt,
          ),
        );
      }
      await database.savePreference('money.setupCompleted', true);
    }
    if (!mounted) return;
    setState(() {
      _enabledModules = result.enabledModules;
      _languageProfile = result.languageProfile;
      _showWorkspaceSetup = false;
      _workspaceSetupCompleted = true;
      _tab = 0;
    });
    unawaited(_trackBetaEvent('workspace_setup_completed', database: database));
  }

  Future<void> _trackBetaEvent(
    String name, {
    LocalDatabase? database,
  }) async {
    final LocalDatabase db;
    if (database != null) {
      db = database;
    } else {
      db = await ref.read(databaseProvider.future);
    }
    if (db.preference('beta.localMetricsEnabled') == false) return;
    final raw = db.preference('beta.metrics');
    final metrics =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final current = metrics[name];
    final currentMap = current is Map
        ? Map<String, dynamic>.from(current)
        : <String, dynamic>{};
    metrics[name] = {
      'count': ((currentMap['count'] as num?)?.toInt() ?? 0) + 1,
      'lastAt': DateTime.now().toUtc().toIso8601String(),
    };
    await db.savePreference('beta.metrics', metrics);
  }

  Widget _modulePage(_WorkspaceModule module, LocalDatabase database) =>
      switch (module.id) {
        'languages' => _languageCourse(database),
        'money' => _module(
            'Деньги',
            Icons.account_balance_wallet_outlined,
            'Доходы, расходы, счета, обязательства и бюджет',
            database,
            CaptureType.expense,
          ),
        'sales' => _module(
            'Продажи',
            Icons.phone_in_talk_outlined,
            'Компании, звонки, следующие шаги и цель на месяц',
            database,
            CaptureType.salesCall,
          ),
        'sport' => _sports(database),
        _ => const SizedBox.shrink(),
      };

  Widget _localStorageError(Object error) {
    if (error is LegacyDataQuarantined) {
      final manager = ref.read(authManagerProvider);
      final count =
          error.tableCounts.values.fold<int>(0, (sum, value) => sum + value);
      final canClaim = manager.restoredExistingSession;
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, size: 32),
                  const SizedBox(height: 16),
                  const Text(
                    'Локальные данные защищены',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Найдена прежняя локальная база ($count записей). Мы не показываем её новому аккаунту автоматически.',
                    style: const TextStyle(height: 1.45),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    canClaim
                        ? 'Вы вошли через восстановленную сессию. Подтвердите перенос только если это ваши данные на этом устройстве.'
                        : 'Чтобы защитить данные, перенос доступен только после восстановления прежней сессии. База сохранена в quarantine и не удалена.',
                    style: TextStyle(color: _secondary, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      ref
                          .read(
                              legacyMigrationEmptyScopeRequestedProvider
                                  .notifier)
                          .state = true;
                      ref.invalidate(databaseProvider);
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text(
                        'Продолжить с пустым пространством'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(manager.logout()),
                    icon: const Icon(Icons.logout_outlined),
                    label: const Text(
                        'Выйти и войти в прежний аккаунт'),
                  ),
                  if (canClaim) ...[
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () {
                        ref
                            .read(
                                legacyMigrationClaimRequestedProvider.notifier)
                            .state = true;
                        ref.invalidate(databaseProvider);
                      },
                      child: const Text('Подтвердить перенос моих данных'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: _ErrorState(message: 'Не удалось открыть SQLite: $error'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(databaseProvider).when(
          loading: () => const Scaffold(
            body: _LoadingState(label: 'Открываем локальное хранилище'),
          ),
          error: (error, _) => _localStorageError(error),
          data: (database) {
            _ensureWorkspaceLoaded(database);
            if (_showWorkspaceSetup) {
              return _WorkspaceSetupScreen(
                database: database,
                modules: _availableModules,
                initialModules: _enabledModules,
                initialLanguageProfile: _languageProfile,
                onComplete: (result) => _saveWorkspaceSetup(database, result),
                onCancel: _workspaceSetupCompleted
                    ? () => setState(() => _showWorkspaceSetup = false)
                    : null,
              );
            }
            final destinations = _destinations;
            final pages = <Widget>[
              _quickCapture(database),
              ..._visibleModules.map(
                (module) => _modulePage(module, database),
              ),
              _account(database),
            ];
            if (_tab >= pages.length) _tab = 0;
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                return Scaffold(
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: _ConsoleBackground(
                          isLight: widget.isLight,
                          animateDarkMesh: true,
                          child: SafeArea(
                            bottom: false,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (wide)
                                  _SideRail(
                                    isLight: widget.isLight,
                                    destinations: destinations,
                                    selectedIndex: _tab,
                                    onSelected: (index) =>
                                        setState(() => _tab = index),
                                  ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      _TopBar(
                                        wide: wide,
                                        isLight: widget.isLight,
                                        manager: ref.read(authManagerProvider),
                                        onToggleTheme: widget.onToggleTheme,
                                        onImport: _importWebBackup,
                                        onSyncInfo: () => setState(() => _notice =
                                            'Синхронизация запускается после подтверждения каждой записи.'),
                                      ),
                                      Expanded(
                                        child: IndexedStack(
                                          index: _tab,
                                          children: pages,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _assistantOverlay(
                        constraints: constraints,
                        wide: wide,
                        sectionLabel: destinations[_tab].label,
                      ),
                    ],
                  ),
                  bottomNavigationBar: wide
                      ? null
                      : NavigationBar(
                          selectedIndex: _tab,
                          onDestinationSelected: (index) =>
                              setState(() => _tab = index),
                          destinations: destinations
                              .map(
                                (destination) => NavigationDestination(
                                  icon: Icon(destination.icon),
                                  label: destination.shortLabel,
                                ),
                              )
                              .toList(),
                        ),
                );
              },
            );
          },
        );
  }

  Widget _quickCapture(LocalDatabase database) {
    if (!_startupSyncStarted) {
      _startupSyncStarted = true;
      Future<void>.microtask(() async {
        try {
          await _syncPending(database);
        } catch (_) {/* retry on next confirmed capture */}
      });
    }
    final summary = database.todaySummary();
    final total = summary.values.fold<int>(0, (a, b) => a + b);

    return _fullScreenQuickCapture(database, summary, total);
  }

  Widget _assistantOverlay({
    required BoxConstraints constraints,
    required bool wide,
    required String sectionLabel,
  }) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final horizontalInset = wide ? 18.0 : 8.0;
    if (!_assistantDockOpen) {
      return Positioned(
        right: horizontalInset + mediaPadding.right,
        bottom: 14 + mediaPadding.bottom,
        child: Semantics(
          button: true,
          label: 'Открыть AI помощника',
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              elevation: 8,
              shadowColor: _amber.withAlpha(80),
            ),
            onPressed: _openAiChat,
            icon: const Icon(Icons.auto_awesome_rounded, size: 19),
            label: const Text('Помощник'),
          ),
        ),
      );
    }

    final minPanelWidth = wide ? 320.0 : 300.0;
    final maxPanelWidth = max(
      minPanelWidth,
      constraints.maxWidth - horizontalInset * 2 - mediaPadding.horizontal,
    );
    return ValueListenableBuilder<_AssistantDockGeometry?>(
      valueListenable: _assistantDockGeometry,
      builder: (context, geometry, _) {
        final defaultPanelWidth = wide
            ? 430.0
            : max(minPanelWidth,
                constraints.maxWidth - 16 - mediaPadding.horizontal);
        final panelWidth = (geometry?.size.width ?? defaultPanelWidth)
            .clamp(minPanelWidth, maxPanelWidth)
            .toDouble();
        final maxPanelHeight = max(280.0, constraints.maxHeight - 24);
        final panelHeight = _assistantDockMinimized
            ? 68.0
            : (geometry?.size.height ?? (wide ? 620.0 : 560.0))
                .clamp(280.0, maxPanelHeight)
                .toDouble();
        final defaultPosition = Offset(
          constraints.maxWidth -
              panelWidth -
              horizontalInset -
              mediaPadding.right,
          constraints.maxHeight - panelHeight - 12 - mediaPadding.bottom,
        );
        final rawPosition = geometry?.position ?? defaultPosition;
        final position = Offset(
          rawPosition.dx
              .clamp(8.0, max(8.0, constraints.maxWidth - panelWidth - 8.0))
              .toDouble(),
          rawPosition.dy
              .clamp(8.0, max(8.0, constraints.maxHeight - panelHeight - 8.0))
              .toDouble(),
        );

        void moveDock(DragUpdateDetails details) {
          final current = _assistantDockGeometry.value ??
              _AssistantDockGeometry(
                position: position,
                size: Size(panelWidth, panelHeight),
              );
          final next = current.position + details.delta;
          _assistantDockGeometry.value = _AssistantDockGeometry(
            position: Offset(
              next.dx
                  .clamp(8.0, max(8.0, constraints.maxWidth - panelWidth - 8.0))
                  .toDouble(),
              next.dy
                  .clamp(
                      8.0, max(8.0, constraints.maxHeight - panelHeight - 8.0))
                  .toDouble(),
            ),
            size: current.size,
          );
        }

        void resizeDock(
          DragUpdateDetails details, {
          double horizontal = 1,
          double vertical = 1,
        }) {
          final current = _assistantDockGeometry.value ??
              _AssistantDockGeometry(
                position: position,
                size: Size(panelWidth, panelHeight),
              );
          var nextPosition = current.position;
          var nextWidth = current.size.width;
          var nextHeight = current.size.height;

          if (horizontal < 0) {
            final right = current.position.dx + current.size.width;
            nextWidth = (current.size.width - details.delta.dx)
                .clamp(minPanelWidth, maxPanelWidth)
                .toDouble();
            nextPosition = Offset(right - nextWidth, nextPosition.dy);
          } else if (horizontal > 0) {
            nextWidth = (current.size.width + details.delta.dx)
                .clamp(minPanelWidth, maxPanelWidth)
                .toDouble();
          }

          if (vertical < 0) {
            final bottom = current.position.dy + current.size.height;
            nextHeight = (current.size.height - details.delta.dy)
                .clamp(280.0, maxPanelHeight)
                .toDouble();
            nextPosition = Offset(nextPosition.dx, bottom - nextHeight);
          } else if (vertical > 0) {
            nextHeight = (current.size.height + details.delta.dy)
                .clamp(280.0, maxPanelHeight)
                .toDouble();
          }

          _assistantDockGeometry.value = _AssistantDockGeometry(
            position: Offset(
              nextPosition.dx
                  .clamp(8.0, max(8.0, constraints.maxWidth - nextWidth - 8.0))
                  .toDouble(),
              nextPosition.dy
                  .clamp(
                      8.0, max(8.0, constraints.maxHeight - nextHeight - 8.0))
                  .toDouble(),
            ),
            size: Size(nextWidth, nextHeight),
          );
        }

        Widget resizeZone({
          double? left,
          double? top,
          double? right,
          double? bottom,
          double? width,
          double? height,
          required SystemMouseCursor cursor,
          double horizontal = 0,
          double vertical = 0,
        }) =>
            Positioned(
              left: left,
              top: top,
              right: right,
              bottom: bottom,
              width: width,
              height: height,
              child: MouseRegion(
                cursor: cursor,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (details) => resizeDock(
                    details,
                    horizontal: horizontal,
                    vertical: vertical,
                  ),
                ),
              ),
            );

        return Positioned(
          left: position.dx,
          top: position.dy,
          width: panelWidth,
          height: panelHeight,
          child: Material(
            elevation: 18,
            color: _base,
            shadowColor: Colors.black.withAlpha(120),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: _amberLine),
            ),
            child: RepaintBoundary(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _assistantDockMinimized
                        ? _MinimizedAssistantDock(
                            sectionLabel: sectionLabel,
                            onDragUpdate: moveDock,
                            onExpand: () =>
                                setState(() => _assistantDockMinimized = false),
                            onClose: () =>
                                setState(() => _assistantDockOpen = false),
                          )
                        : _TelegramAssistantChat(
                            controller: _assistantText,
                            messages: _chatMessages,
                            attachments: _chatAttachments,
                            draft: _draft,
                            busy: _chatBusy,
                            listening: _listening,
                            error: _chatError,
                            memoryCandidateId: _chatMemoryCandidateId,
                            selectedModel: _selectedAiModel,
                            onModelChanged: (value) =>
                                setState(() => _selectedAiModel = value),
                            models: _aiModels,
                            onSend: _sendAssistantMessage,
                            onPickImages: _pickChatImages,
                            onRemoveAttachment: _removeChatAttachment,
                            onListen: _listenForAssistant,
                            onSave: _save,
                            onEdit: () => setState(() => _draft = null),
                            onCancel: () => setState(() => _draft = null),
                            onMemoryDecision: _decideChatMemory,
                            sportProposal: _sportPlanProposal,
                            onSportPlanDecision: _decideSportPlanProposal,
                            composerFocus: _composerFocus,
                            fillHeight: true,
                            sectionLabel: sectionLabel,
                            onDragUpdate: moveDock,
                            onMinimize: () =>
                                setState(() => _assistantDockMinimized = true),
                            onClose: () =>
                                setState(() => _assistantDockOpen = false),
                          ),
                  ),
                  resizeZone(
                    left: 0,
                    top: 14,
                    bottom: 14,
                    width: 8,
                    cursor: SystemMouseCursors.resizeLeftRight,
                    horizontal: -1,
                  ),
                  resizeZone(
                    right: 0,
                    top: 14,
                    bottom: 14,
                    width: 8,
                    cursor: SystemMouseCursors.resizeLeftRight,
                  ),
                  resizeZone(
                    left: 14,
                    top: 0,
                    right: 14,
                    height: 8,
                    cursor: SystemMouseCursors.resizeUpDown,
                    vertical: -1,
                  ),
                  resizeZone(
                    left: 14,
                    right: 14,
                    bottom: 0,
                    height: 8,
                    cursor: SystemMouseCursors.resizeUpDown,
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: resizeDock,
                        child: const SizedBox(width: 14, height: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fullScreenQuickCapture(
    LocalDatabase database,
    Map<String, int> summary,
    int total,
  ) =>
      _PageScroll(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              eyebrow: 'СЕГОДНЯ',
              title: total == 0
                  ? 'С чего хотите начать?'
                  : 'Сегодня уже есть $total ${_recordWord(total)}',
              description:
                  'Запишите событие одной фразой или откройте нужный раздел. Умный помощник доступен отдельно и не мешает обычному ведению данных.',
              trailing: const _ModuleIcon(icon: Icons.today_outlined),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _WeeklyReviewDialog(
                    database: database,
                    enabledModules: _enabledModules,
                    targetLanguage:
                        _languageProfile['targetLanguage'] as String? ?? 'Язык',
                  ),
                ),
                icon: const Icon(Icons.insights_outlined, size: 18),
                label: const Text('Итоги 7 дней'),
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final capture = _capturePanel();
                final status = Column(
                  children: [
                    _TodaySidePanel(
                      summary: summary,
                      total: total,
                      enabledModules: _enabledModules,
                      targetLanguage:
                          _languageProfile['targetLanguage'] as String? ??
                              'Язык',
                    ),
                    const SizedBox(height: 12),
                    _nextBestActionCard(total),
                  ],
                );
                if (constraints.maxWidth < 880) {
                  return Column(
                      children: [capture, const SizedBox(height: 12), status]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: capture),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: status),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              eyebrow: 'ВАШЕ ПРОСТРАНСТВО',
              title: _visibleModules.isEmpty
                  ? 'Добавьте первый раздел'
                  : 'Продолжить в разделе',
              trailing: TextButton.icon(
                onPressed: () => setState(() => _showWorkspaceSetup = true),
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('Настроить'),
              ),
            ),
            const SizedBox(height: 12),
            if (_visibleModules.isEmpty)
              _HoverPanel(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: _amber),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Выберите язык, деньги, тренировки или рабочие продажи. Данные скрытых разделов не удаляются.',
                        style: TextStyle(color: _secondary, height: 1.4),
                      ),
                    ),
                    FilledButton(
                      onPressed: () =>
                          setState(() => _showWorkspaceSetup = true),
                      child: const Text('Выбрать'),
                    ),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth < 620
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _visibleModules.map((module) {
                      return SizedBox(
                        width: width,
                        child: _HoverPanel(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: _amber.withAlpha(22),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(module.icon, color: _amber),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(module.label,
                                        style: TextStyle(
                                            color: _primary,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 3),
                                    Text(module.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: _secondary,
                                            fontSize: 11,
                                            height: 1.35)),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Открыть ${module.label}',
                                onPressed: () => _openModule(module.id),
                                icon: const Icon(Icons.arrow_forward_rounded),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      );

  Widget _nextBestActionCard(int total) {
    final module = _visibleModules.isEmpty ? null : _visibleModules.first;
    final noModules = module == null;
    final firstRecord = total == 0;

    final title = noModules
        ? 'Выберите один полезный раздел'
        : firstRecord
            ? 'Первый результат за минуту'
            : 'Продолжите там, где это полезно';
    final description = noModules
        ? 'Начните с одного направления. Остальные можно подключить позже без потери данных.'
        : firstRecord
            ? switch (module!.id) {
                'money' =>
                  'Введите обычной фразой первый расход — сумму и счёт можно проверить до сохранения.',
                'languages' =>
                  'Откройте персональный план и выполните первое короткое занятие.',
                'sport' =>
                  'Откройте безопасный план и отметьте первую тренировку.',
                'sales' =>
                  'Добавьте первый звонок или следующий шаг по клиенту.',
                _ => 'Откройте раздел и сделайте первый шаг.',
              }
            : 'Сегодня уже есть данные. Откройте ${module!.label.toLowerCase()} и посмотрите прогресс.';
    final buttonLabel = noModules
        ? 'Выбрать раздел'
        : module!.id == 'money' && firstRecord
            ? 'Подставить пример'
            : 'Открыть ${module.shortLabel.toLowerCase()}';

    return _HoverPanel(
      color: _elevated,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.assistant_navigation, color: _amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelKicker(icon: Icons.flag_outlined, label: 'СЛЕДУЮЩИЙ ШАГ'),
                const SizedBox(height: 8),
                Text(title,
                    style: TextStyle(
                        color: _primary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(
                        color: _secondary, fontSize: 12, height: 1.4)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    if (noModules) {
                      setState(() => _showWorkspaceSetup = true);
                    } else if (module!.id == 'money' && firstRecord) {
                      setState(() => _text.text =
                          'Потратил 20 000 сум на кофе с основной карты');
                    } else {
                      _openModule(module.id);
                    }
                  },
                  icon: Icon(
                      noModules
                          ? Icons.add_rounded
                          : Icons.arrow_forward_rounded,
                      size: 17),
                  label: Text(buttonLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _recordWord(int value) {
    final tail = value % 100;
    if (tail >= 11 && tail <= 14) return 'записей';
    return switch (value % 10) {
      1 => 'запись',
      2 || 3 || 4 => 'записи',
      _ => 'записей',
    };
  }

  void _openModule(String id) {
    final index = _visibleModules.indexWhere((module) => module.id == id);
    if (index >= 0) setState(() => _tab = index + 1);
  }

  Widget _capturePanel() => _HoverPanel(
        borderColor: _amberLine,
        glowOnHover: true,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelKicker(icon: Icons.bolt, label: 'НОВАЯ ЗАПИСЬ'),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText:
                    'Например: Купил бутылку колы за 20 тысяч сум наличными',
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: IconButton(
                    tooltip:
                        _listening ? 'Остановить запись' : 'Голосовой ввод',
                    onPressed: _listenForCapture,
                    icon: Icon(
                      _listening ? Icons.stop_circle : Icons.mic_none,
                      color: _listening ? _red : _amber,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _parse,
                    icon: _busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _tertiary,
                            ),
                          )
                        : Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(_busy ? 'ПРОВЕРЯЕМ…' : 'ПРОВЕРИТЬ ЗАПИСЬ'),
                  ),
                ),
                const SizedBox(width: 10),
                _KeyboardHint(label: 'ВВОД', onTap: _busy ? null : _parse),
              ],
            ),
            if (_draft != null) ...[
              const SizedBox(height: 18),
              _ReviewCard(
                draft: _draft!,
                onSave: _save,
                onEdit: () => setState(() => _draft = null),
                onCancel: () => setState(() {
                  _draft = null;
                  _text.clear();
                }),
              ),
            ],
            if (_canonicalMoneyDraft != null) ...[
              const SizedBox(height: 18),
              _CanonicalMoneyReviewCard(
                envelope: _canonicalMoneyDraft!,
                busy: _busy,
                onConfirm: _confirmCanonicalMoney,
                onEdit: _editCanonicalMoney,
                onCancel: _cancelCanonicalMoneyReview,
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 14),
              _NoticeBanner(message: _notice!),
              if (_canonicalSyncRepairAvailable)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _repairCanonicalMoneySync,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Повторить синхронизацию'),
                  ),
                ),
            ],
          ],
        ),
      );

  Widget _module(
    String name,
    IconData icon,
    String description,
    LocalDatabase database,
    CaptureType type,
  ) =>
      _ModuleScreen(
        name: name,
        icon: icon,
        description: description,
        database: database,
        type: type,
        onCapture: () => setState(() => _tab = 0),
      );

  Widget _languageCourse(LocalDatabase database) => _EnglishRoadmapScreen(
        database: database,
        manager: ref.read(authManagerProvider),
        targetLanguage:
            _languageProfile['targetLanguage'] as String? ?? 'Английский',
        languageProfile: _languageProfile,
        onCapture: () => setState(() => _tab = 0),
        onChanged: () => setState(() {}),
      );

  Widget _sports(LocalDatabase database) => _SportsRoadmapScreen(
        database: database,
        onCapture: () => setState(() => _tab = 0),
        onChanged: () => setState(() {}),
      );

  void _openAiChat() {
    final initialMessage = _text.text.trim();
    setState(() {
      if (initialMessage.isNotEmpty && _assistantText.text.trim().isEmpty) {
        _assistantText.text = initialMessage;
      }
      _assistantDockOpen = true;
      _assistantDockMinimized = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _composerFocus.requestFocus();
    });
    unawaited(_trackBetaEvent('assistant_opened'));
  }

  Widget _account(LocalDatabase database) => _AccountScreen(
        database: database,
        session: widget.session,
        manager: ref.read(authManagerProvider),
        isLight: widget.isLight,
        onToggleTheme: widget.onToggleTheme,
        enabledModules: _enabledModules,
        onCustomizeWorkspace: () => setState(() {
          _showWorkspaceSetup = true;
          _tab = 0;
        }),
      );
}

class _AccountScreen extends StatelessWidget {
  const _AccountScreen({
    required this.database,
    required this.session,
    required this.manager,
    required this.isLight,
    required this.onToggleTheme,
    required this.enabledModules,
    required this.onCustomizeWorkspace,
  });

  final LocalDatabase database;
  final BetaSession session;
  final SessionManager manager;
  final bool isLight;
  final VoidCallback onToggleTheme;
  final Set<String> enabledModules;
  final VoidCallback onCustomizeWorkspace;

  String _sectionCount(int value) {
    final tail = value % 100;
    if (tail >= 11 && tail <= 14) return '$value выбранных разделов';
    return switch (value % 10) {
      1 => '$value выбранный раздел',
      2 || 3 || 4 => '$value выбранных раздела',
      _ => '$value выбранных разделов',
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeTenant = session.activeTenant;
    return _PageScroll(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              eyebrow: 'АККАУНТ / НАСТРОЙКИ',
              title: 'Ваш аккаунт и данные',
              description:
                  'Здесь находятся разделы, оформление, поддержка и управление умными функциями. Обычные записи и ваши данные не зависят от AI.',
              trailing: Icon(Icons.person_outline_rounded, color: _amber),
            ),
            const SizedBox(height: 20),
            _HoverPanel(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _amber.withAlpha(24),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.person_rounded, color: _amber),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.user.displayName,
                            style: TextStyle(
                                color: _primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(activeTenant?.name ?? 'Личное пространство',
                            style: TextStyle(color: _secondary)),
                      ],
                    ),
                  ),
                  if (session.tenants.length > 1)
                    PopupMenuButton<String>(
                      tooltip: 'Сменить пространство',
                      onSelected: manager.switchTenant,
                      itemBuilder: (_) => session.tenants
                          .map((tenant) => PopupMenuItem(
                              value: tenant.id, child: Text(tenant.name)))
                          .toList(),
                      child: const Chip(label: Text('Сменить')),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _HoverPanel(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _amber.withAlpha(22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Icon(Icons.dashboard_customize_outlined, color: _amber),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ваши разделы',
                            style: TextStyle(
                                color: _primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(
                          enabledModules.isEmpty
                              ? 'Только главная и быстрые записи'
                              : '${_sectionCount(enabledModules.length)}. Их можно менять без потери данных.',
                          style: TextStyle(color: _secondary, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: onCustomizeWorkspace,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Настроить разделы'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _HoverPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PanelKicker(
                      icon: Icons.auto_awesome_rounded, label: 'УМНЫЕ ФУНКЦИИ'),
                  const SizedBox(height: 12),
                  Text('Подключаются только там, где действительно помогают',
                      style: TextStyle(
                          color: _primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  Text(
                    'Можно попросить объяснить, составить план или разобрать текст. Финансовые записи сначала показываются вам на проверку, а ручной ввод, история и прогресс работают без умного помощника.',
                    style: TextStyle(color: _secondary, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Если помощник предлагает что-то запомнить, это не сохраняется постоянно без вашего подтверждения.',
                    style:
                        TextStyle(color: _tertiary, fontSize: 12, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _AiCreditsDialog(manager: manager),
                    ),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Статус умных функций'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _PrivacyDialog(
                        database: database,
                        enabledModules: enabledModules,
                      ),
                    ),
                    icon: const Icon(Icons.privacy_tip_outlined),
                    label: const Text('Приватность и данные'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _HoverPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PanelKicker(icon: Icons.tune_rounded, label: 'НАСТРОЙКИ'),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text('Светлая тема', style: TextStyle(color: _primary)),
                    subtitle: Text('Переключите оформление приложения',
                        style: TextStyle(color: _secondary)),
                    value: isLight,
                    onChanged: (_) => onToggleTheme(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _HoverPanel(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width =
                      constraints.maxWidth < 480 ? constraints.maxWidth : 230.0;
                  Widget item(Widget child) => SizedBox(
                        width: width,
                        height: 48,
                        child: child,
                      );
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      item(OutlinedButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => _FeedbackDialog(manager: manager),
                        ),
                        icon: const Icon(Icons.feedback_outlined),
                        label: const Text('Обратная связь'),
                      )),
                      item(OutlinedButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => _DiagnosticsDialog(
                              manager: manager, session: session),
                        ),
                        icon: const Icon(Icons.monitor_heart_outlined),
                        label: const Text('Диагностика'),
                      )),
                      item(OutlinedButton.icon(
                        onPressed: manager.logout,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Выйти из аккаунта'),
                      )),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.isLight,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final bool isLight;
  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        width: 232,
        padding: const EdgeInsets.fromLTRB(18, 20, 14, 18),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(right: BorderSide(color: _line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    isLight
                        ? 'assets/brand/codev-tim-logo-light.png'
                        : 'assets/brand/codev-tim-logo.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CODEV_TIM',
                      style: TextStyle(
                        color: _primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'CODEV ASSISTANT',
                      style: TextStyle(
                        color: _tertiary,
                        fontFamily: 'Cascadia Mono',
                        fontSize: 9,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 40),
            _RailLabel('ЛИЧНОЕ'),
            const SizedBox(height: 8),
            for (final entry in destinations.indexed) ...[
              if (entry.$2.id == 'sales') ...[
                const SizedBox(height: 14),
                _RailLabel('РАБОТА'),
                const SizedBox(height: 8),
              ],
              if (entry.$2.id == 'account') ...[
                const SizedBox(height: 14),
                _RailLabel('НАСТРОЙКИ'),
                const SizedBox(height: 8),
              ],
              _RailItem(
                destination: entry.$2,
                selected: selectedIndex == entry.$1,
                onTap: () => onSelected(entry.$1),
              ),
            ],
            const Spacer(),
            Divider(color: _line),
            const SizedBox(height: 12),
            Row(
              children: [
                _PulseDot(),
                SizedBox(width: 8),
                Text(
                  'ДАННЫЕ НА УСТРОЙСТВЕ · ГОТОВО',
                  style: TextStyle(
                    color: _secondary,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(8),
            hoverColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStatePropertyAll(Colors.transparent),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: selected ? 13 : 11,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: selected ? _amber.withAlpha(28) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? _amberLine : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    destination.icon,
                    size: 18,
                    color: selected ? _amber : _tertiary,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      destination.label,
                      style: TextStyle(
                        color: selected ? _primary : _secondary,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.wide,
    required this.isLight,
    required this.manager,
    required this.onToggleTheme,
    required this.onImport,
    required this.onSyncInfo,
  });

  final bool wide;
  final bool isLight;
  final SessionManager manager;
  final VoidCallback onToggleTheme;
  final VoidCallback onImport;
  final VoidCallback onSyncInfo;

  @override
  Widget build(BuildContext context) => Container(
        height: wide ? 68 : 64,
        padding: EdgeInsets.symmetric(horizontal: wide ? 30 : 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(
          children: [
            if (!wide) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  isLight
                      ? 'assets/brand/codev-tim-logo-light.png'
                      : 'assets/brand/codev-tim-logo.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Text(
                'ВАШ ДЕНЬ  /  БЫСТРЫЕ ЗАПИСИ',
                style: TextStyle(
                  color: _tertiary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 10,
                  letterSpacing: 0.7,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: onImport,
              tooltip: 'Импортировать резервную копию',
              icon: Icon(Icons.file_upload_outlined, size: 20),
              color: _secondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            IconButton(
              onPressed: onSyncInfo,
              tooltip: 'Статус синхронизации',
              icon: Icon(Icons.sync, size: 20),
              color: _secondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            IconButton(
              onPressed: onToggleTheme,
              tooltip: isLight ? 'Тёмная тема' : 'Светлая тема',
              icon: Icon(
                isLight ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                size: 20,
              ),
              color: _secondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      );
}

class _PageScroll extends StatefulWidget {
  const _PageScroll({required this.child});

  final Widget child;

  @override
  State<_PageScroll> createState() => _PageScrollState();
}

class _PageScrollState extends State<_PageScroll> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          final left = narrow ? 12.0 : 30.0;
          final right = narrow ? 12.0 : 18.0;
          return ScrollbarTheme(
            data: ScrollbarThemeData(
              thumbColor: WidgetStatePropertyAll(_amber.withAlpha(190)),
              trackColor: WidgetStatePropertyAll(_line),
              trackBorderColor: WidgetStatePropertyAll(Colors.transparent),
              crossAxisMargin: 0,
              mainAxisMargin: 8,
              thickness: WidgetStatePropertyAll(5),
              radius: const Radius.circular(99),
              thumbVisibility: WidgetStatePropertyAll(true),
              trackVisibility: WidgetStatePropertyAll(true),
            ),
            child: Scrollbar(
              controller: _controller,
              thumbVisibility: true,
              trackVisibility: true,
              scrollbarOrientation: ScrollbarOrientation.right,
              child: SingleChildScrollView(
                controller: _controller,
                padding: EdgeInsets.fromLTRB(left, narrow ? 16 : 30, right, 42),
                child: SizedBox(
                  width: constraints.maxWidth - left - right,
                  child: widget.child,
                ),
              ),
            ),
          );
        },
      );
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.eyebrow,
    required this.title,
    required this.description,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AmberEyebrow(eyebrow),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: _primary,
                  fontSize: narrow ? 24 : 30,
                  height: 1.12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: Text(
                  description,
                  style: TextStyle(
                    color: _secondary,
                    fontSize: narrow ? 13 : 14,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          );
          if (trailing == null) return copy;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 12), trailing!],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: copy),
              const SizedBox(width: 14),
              trailing!
            ],
          );
        },
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AmberEyebrow(eyebrow),
              const SizedBox(height: 5),
              Text(
                title,
                style: TextStyle(
                  color: _primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      );
}

class _CommandPrimer extends StatelessWidget {
  const _CommandPrimer();

  @override
  Widget build(BuildContext context) => _HoverPanel(
        color: _surface,
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelKicker(
                icon: Icons.lightbulb_outline, label: 'КАК МОЖНО НАПИСАТЬ'),
            SizedBox(height: 14),
            Text(
              'Одна фраза — одна понятная запись.',
              style: TextStyle(
                color: _primary,
                fontSize: 17,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 14),
            _ExampleLine(label: 'ДЕНЬГИ', text: 'кофе 18 000 сум, карта'),
            _ExampleLine(label: 'ПРОДАЖИ', text: 'позвонил в Acme, ждём ответ'),
            _ExampleLine(label: 'СПОРТ', text: 'бег 30 минут'),
            _ExampleLine(label: 'АНГЛИЙСКИЙ', text: 'занимался 20 минут'),
            SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 15, color: _green),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Сначала вы проверяете запись — только потом она сохраняется и синхронизируется.',
                    style: TextStyle(color: _secondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ExampleLine extends StatelessWidget {
  const _ExampleLine({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 58,
              child: Text(
                label,
                style: TextStyle(
                  color: _amber,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: _secondary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      );
}

class _TodayCompactStrip extends StatelessWidget {
  const _TodayCompactStrip({required this.summary, required this.total});

  final Map<String, int> summary;
  final int total;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Text('Сегодня',
              style: TextStyle(
                  color: _primary, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(width: 14),
          _TodayMini(label: 'Записи', value: '$total'),
          _TodayMini(label: 'Расходы', value: '${summary['expense'] ?? 0}'),
          _TodayMini(label: 'Продажи', value: '${summary['sales_call'] ?? 0}'),
          _TodayMini(label: 'Английский', value: '${summary['english'] ?? 0}'),
          _TodayMini(label: 'Тренировки', value: '${summary['sports'] ?? 0}'),
        ]),
      );
}

class _TodayMini extends StatelessWidget {
  const _TodayMini({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: _tertiary, fontSize: 11)),
          const SizedBox(width: 5),
          Text(value,
              style: TextStyle(
                  color: _amber,
                  fontFamily: 'Cascadia Mono',
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

class _TodayChatRail extends StatelessWidget {
  const _TodayChatRail({required this.summary, required this.total});

  final Map<String, int> summary;
  final int total;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _base.withAlpha(190),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _amberLine),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Сегодня',
              style: TextStyle(
                  color: _primary, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('$total записей',
              style: TextStyle(
                  color: _amber,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: _line),
          ),
          _TodayRailMetric(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Деньги',
              value: summary['expense'] ?? 0),
          _TodayRailMetric(
              icon: Icons.phone_in_talk_outlined,
              label: 'Продажи',
              value: summary['sales_call'] ?? 0),
          _TodayRailMetric(
              icon: Icons.menu_book_outlined,
              label: 'Английский',
              value: summary['english'] ?? 0),
          _TodayRailMetric(
              icon: Icons.fitness_center_outlined,
              label: 'Тренировки',
              value: summary['sports'] ?? 0),
        ]),
      );
}

class _TodayRailMetric extends StatelessWidget {
  const _TodayRailMetric(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(icon, color: _tertiary, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: TextStyle(color: _secondary, fontSize: 11))),
          Text('$value',
              style: TextStyle(
                  color: _amber,
                  fontFamily: 'Cascadia Mono',
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

class _WeeklyReviewDialog extends StatelessWidget {
  const _WeeklyReviewDialog({
    required this.database,
    required this.enabledModules,
    required this.targetLanguage,
  });

  final LocalDatabase database;
  final Set<String> enabledModules;
  final String targetLanguage;

  String _money(num value) =>
      '${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => ' ')} сум';

  @override
  Widget build(BuildContext context) {
    final threshold = DateTime.now().subtract(const Duration(days: 7));
    final records = database
        .all()
        .where((record) => record.createdAt.isAfter(threshold))
        .toList();
    int count(CaptureType type) =>
        records.where((record) => record.draft.type == type).length;
    final expenses = records
        .where((record) => record.draft.type == CaptureType.expense)
        .fold<double>(0, (sum, record) => sum + (record.draft.amount ?? 0));
    final income = records
        .where((record) => record.draft.type == CaptureType.income)
        .fold<double>(0, (sum, record) => sum + (record.draft.amount ?? 0));
    final completedLanguage = database.preference(
      'language.completed.${targetLanguage.trim().toLowerCase()}',
    );
    final languageDays =
        completedLanguage is List ? completedLanguage.length : 0;
    final activeObligations = database
        .moneyObligations()
        .where((item) => item.status == 'active')
        .length;

    final values = <String, int>{
      'languages': max(languageDays, count(CaptureType.english)),
      'money': count(CaptureType.expense) + count(CaptureType.income),
      'sport': count(CaptureType.sports),
      'sales': count(CaptureType.salesCall),
    };
    final quietModule = enabledModules.cast<String?>().firstWhere(
          (id) => (values[id] ?? 0) == 0,
          orElse: () => null,
        );
    final nextStep = quietModule == null
        ? 'Вы поддерживали все выбранные направления. На следующую неделю достаточно сохранить тот же ритм.'
        : switch (quietModule) {
            'languages' =>
              'Сделайте одно короткое занятие по $targetLanguage — без попытки наверстать всю неделю.',
            'money' =>
              'Запишите один реальный расход и проверьте остаток. Этого достаточно, чтобы вернуть финансовую картину.',
            'sport' =>
              'Запланируйте одну посильную тренировку или восстановительную сессию.',
            'sales' =>
              'Зафиксируйте один следующий шаг по самому важному рабочему контакту.',
            _ => 'Выберите один небольшой шаг на следующую неделю.',
          };

    Widget metric(String label, String value, IconData icon) => _HoverPanel(
          color: _elevated,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: _amber, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(color: _secondary, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(value,
                        style: TextStyle(
                            color: _primary, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        );

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.insights_outlined),
          SizedBox(width: 10),
          Text('Итоги 7 дней'),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                records.isEmpty
                    ? 'За неделю пока нет подтверждённых быстрых записей. Это не ошибка — начните с одного события.'
                    : 'За неделю подтверждено ${records.length} записей. Ниже только факты из локальной базы, без AI-догадок.',
                style: TextStyle(color: _secondary, height: 1.45),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth < 520
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (enabledModules.contains('money'))
                        SizedBox(
                          width: width,
                          child: metric(
                              'Расходы / доходы',
                              '${_money(expenses)} / ${_money(income)}',
                              Icons.account_balance_wallet_outlined),
                        ),
                      if (enabledModules.contains('languages'))
                        SizedBox(
                          width: width,
                          child: metric('Языковые занятия', '$languageDays',
                              Icons.translate_rounded),
                        ),
                      if (enabledModules.contains('sport'))
                        SizedBox(
                          width: width,
                          child: metric('Тренировки', '${values['sport']}',
                              Icons.fitness_center_outlined),
                        ),
                      if (enabledModules.contains('sales'))
                        SizedBox(
                          width: width,
                          child: metric(
                              'Рабочие follow-up',
                              '${values['sales']}',
                              Icons.phone_in_talk_outlined),
                        ),
                    ],
                  );
                },
              ),
              if (enabledModules.contains('money') &&
                  activeObligations > 0) ...[
                const SizedBox(height: 12),
                Text('Активных обязательств: $activeObligations',
                    style: TextStyle(color: _secondary)),
              ],
              const SizedBox(height: 18),
              _HoverPanel(
                borderColor: _amberLine,
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag_outlined, color: _amber),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Один следующий шаг',
                              style: TextStyle(
                                  color: _primary,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          Text(nextStep,
                              style:
                                  TextStyle(color: _secondary, height: 1.45)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Понятно'),
        ),
      ],
    );
  }
}

class _TodaySidePanel extends StatelessWidget {
  const _TodaySidePanel({
    required this.summary,
    required this.total,
    required this.enabledModules,
    required this.targetLanguage,
  });

  final Map<String, int> summary;
  final int total;
  final Set<String> enabledModules;
  final String targetLanguage;

  @override
  Widget build(BuildContext context) {
    return _HoverPanel(
      color: Colors.transparent,
      borderColor: _amberLine,
      glowOnHover: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Сегодня',
              style: TextStyle(
                  color: _primary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Сводка по подтверждённым записям',
              style: TextStyle(color: _tertiary, fontSize: 11)),
          const SizedBox(height: 18),
          _TodayStat(label: 'Всего записей', value: '$total'),
          if (enabledModules.contains('money'))
            _TodayStat(label: 'Расходы', value: '${summary['expense'] ?? 0}'),
          if (enabledModules.contains('languages'))
            _TodayStat(
                label: targetLanguage, value: '${summary['english'] ?? 0}'),
          if (enabledModules.contains('sport'))
            _TodayStat(label: 'Тренировки', value: '${summary['sports'] ?? 0}'),
          if (enabledModules.contains('sales'))
            _TodayStat(
                label: 'Продажи', value: '${summary['sales_call'] ?? 0}'),
          const SizedBox(height: 18),
          Divider(color: _line),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.shield_outlined, size: 16, color: _green),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Сохранение — только после подтверждения.',
                  style:
                      TextStyle(color: _secondary, fontSize: 11, height: 1.35)),
            ),
          ]),
        ],
      ),
    );
  }
}

class _TodayStat extends StatelessWidget {
  const _TodayStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: _secondary))),
          Text(value,
              style: TextStyle(
                  color: _primary,
                  fontFamily: 'Cascadia Mono',
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.summary});

  final Map<String, int> summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final cards = [
            (
              'ВСЕ ЗАПИСИ',
              '${summary.values.fold<int>(0, (a, b) => a + b)}',
              Icons.data_object
            ),
            ('РАСХОДЫ', '${summary['expense'] ?? 0}', Icons.payments_outlined),
            (
              'ЗВОНКИ ПО ПРОДАЖАМ',
              '${summary['sales_call'] ?? 0}',
              Icons.call_outlined
            ),
          ];
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards
                .map(
                  (card) => SizedBox(
                    width: constraints.maxWidth >= 620
                        ? (constraints.maxWidth - 24) / 3
                        : constraints.maxWidth,
                    child: _MetricCard(
                      label: card.$1,
                      value: card.$2,
                      icon: card.$3,
                    ),
                  ),
                )
                .toList(),
          );
        },
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => _HoverPanel(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _amber.withAlpha(18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _amberLine),
              ),
              child: Icon(icon, size: 18, color: _amber),
            ),
            const SizedBox(width: 13),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: _tertiary,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 10,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: _primary,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) => _HoverPanel(
        color: _elevated,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PulseDot(color: _green),
            SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'КАК ХРАНЯТСЯ ДАННЫЕ',
                    style: TextStyle(
                      color: _primary,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Подтверждённые записи сначала сохраняются на этом устройстве. Если сети нет, они дождутся синхронизации. Финансовая запись не сохранится без вашего подтверждения.',
                    style: TextStyle(
                      color: _secondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 16),
            Text(
              'НАДЁЖНО\nЛОКАЛЬНО',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _green,
                fontFamily: 'Cascadia Mono',
                fontSize: 10,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

String _captureTypeRussian(CaptureType type) => switch (type) {
      CaptureType.expense => 'Расход',
      CaptureType.income => 'Доход',
      CaptureType.salesCall => 'Продажа',
      CaptureType.english => 'Английский',
      CaptureType.sports => 'Тренировка',
    };

class _CanonicalMoneyReviewCard extends StatelessWidget {
  const _CanonicalMoneyReviewCard({
    required this.envelope,
    required this.busy,
    required this.onConfirm,
    required this.onEdit,
    required this.onCancel,
  });

  final CaptureEnvelopeV2 envelope;
  final bool busy;
  final VoidCallback onConfirm, onEdit, onCancel;

  String _exactAmount(MoneyIntentV2 intent) {
    final scale = intent.currency == 'UZS' ? 0 : 2;
    final raw = BigInt.parse(intent.minorUnits).toString();
    if (scale == 0) return raw;
    final padded = raw.padLeft(scale + 1, '0');
    return '${padded.substring(0, padded.length - scale)}.${padded.substring(padded.length - scale)}';
  }

  @override
  Widget build(BuildContext context) {
    final intent = envelope.intent as MoneyIntentV2;
    final income = intent.direction.name == 'income';
    final lower = envelope.originalText.toLowerCase();
    final salaryHint = RegExp(r'зарплат|зп|salary|maosh|ойлик').hasMatch(lower);
    final cardHint =
        salaryHint || RegExp(r'карт|карта|card|bank card').hasMatch(lower);
    final when = envelope.occurredAt ?? envelope.createdAt;
    final rows = <(String, String)>[
      ('Тип', income ? 'Доход' : 'Расход'),
      ('Сумма', '${_exactAmount(intent)} ${intent.currency}'),
      ('Дата', when.toLocal().toString().substring(0, 16)),
      (
        'Счёт',
        intent.account == 'unassigned'
            ? (cardHint ? 'Предположение: Карта' : 'Не указан')
            : intent.account
      ),
      (
        'Категория',
        intent.category == 'unclassified'
            ? (salaryHint ? 'Предположение: Зарплата' : 'Не классифицировано')
            : intent.category
      ),
      ('Описание', intent.description ?? envelope.originalText),
      ('Назначение', 'Money'),
    ];
    return _HoverPanel(
      borderColor: _amberLine,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelKicker(
              icon: Icons.account_balance_wallet_outlined,
              label: 'ПРОВЕРКА MONEY'),
          const SizedBox(height: 12),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                SizedBox(
                    width: 112,
                    child: Text(row.$1, style: TextStyle(color: _secondary))),
                Expanded(child: Text(row.$2)),
              ]),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : onConfirm,
                child: Text(busy ? 'СОХРАНЯЕМ…' : 'ПОДТВЕРДИТЬ'),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
                onPressed: busy ? null : onEdit, child: const Text('ИЗМЕНИТЬ')),
            TextButton(
                onPressed: busy ? null : onCancel, child: const Text('ОТМЕНА')),
          ]),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.draft,
    required this.onSave,
    required this.onEdit,
    required this.onCancel,
  });

  final CaptureDraft draft;
  final VoidCallback onSave;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 620;
    return Container(
      decoration: BoxDecoration(
        color: _base.withAlpha(225),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _amberLine),
      ),
      padding: EdgeInsets.all(narrow ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined,
                  color: _amber, size: narrow ? 17 : 19),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'ПРОВЕРЬТЕ ПЕРЕД СОХРАНЕНИЕМ',
                  style: TextStyle(
                    color: _primary,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              _TypeChip(type: _captureTypeRussian(draft.type)),
            ],
          ),
          const SizedBox(height: 14),
          ..._fields(),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: _amber,
                      foregroundColor: _base,
                      visualDensity: narrow
                          ? VisualDensity.compact
                          : VisualDensity.standard),
                  onPressed: onSave,
                  icon: Icon(Icons.check, size: 17),
                  label: Text('СОХРАНИТЬ'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onEdit,
                  child: Text('ИЗМЕНИТЬ'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onCancel,
                  child: Text('ОТМЕНИТЬ'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _fields() {
    final fields = <String, String?>{
      'Тип': _captureTypeRussian(draft.type),
      'Сумма': draft.amount == null
          ? null
          : '${draft.amount!.round()} ${draft.currency}',
      'Категория': _captureValueRussian(draft.category),
      'Способ оплаты': _captureValueRussian(draft.paymentMethod),
      'Описание': draft.description,
      'Компания': draft.company,
      'Результат': draft.result,
      'Следующий шаг': draft.nextStep,
      'Дата follow-up': draft.followUpDate,
      'Длительность':
          draft.durationMinutes == null ? null : '${draft.durationMinutes} мин',
      'Активность': draft.activityType,
      'Задание': draft.completedTask,
    };
    return fields.entries
        .where((entry) => entry.value != null && entry.value!.isNotEmpty)
        .map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    entry.key.toUpperCase(),
                    style: TextStyle(
                      color: _tertiary,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 9,
                      letterSpacing: 0.45,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value!,
                    style: TextStyle(
                      color: _primary,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}

class _SportPlanProposalCard extends StatelessWidget {
  const _SportPlanProposalCard({
    required this.proposal,
    required this.onApply,
    required this.onCancel,
  });

  final _SportPlanProposal proposal;
  final VoidCallback onApply;
  final VoidCallback onCancel;

  Future<void> _openResource() async {
    final resource = proposal.resource;
    if (resource != null) {
      await launchUrl(Uri.parse(resource.url),
          mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _base.withAlpha(220),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: proposal.kind == _SportPlanProposalKind.injuryPause
                  ? _red.withAlpha(180)
                  : _amberLine),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
                proposal.kind == _SportPlanProposalKind.injuryPause
                    ? Icons.health_and_safety_outlined
                    : Icons.directions_run_outlined,
                color: proposal.kind == _SportPlanProposalKind.injuryPause
                    ? _red
                    : _amber),
            const SizedBox(width: 9),
            Text('КОРРЕКТИРОВКА ПЛАНА',
                style: TextStyle(
                    color: _primary,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Text(proposal.reply,
              style: TextStyle(color: _secondary, height: 1.4)),
          if (proposal.resource != null)
            TextButton.icon(
              onPressed: _openResource,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(proposal.resource!.title),
            ),
          const SizedBox(height: 12),
          Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(onPressed: onApply, child: const Text('ПРИМЕНИТЬ')),
            const SizedBox(width: 8),
            TextButton(onPressed: onCancel, child: const Text('НЕ МЕНЯТЬ')),
          ]),
        ]),
      );
}

String? _captureValueRussian(String? value) => switch (value) {
      'other' => 'Другое',
      'salary' => 'Предположение: Зарплата',
      'cash' => 'Наличные',
      'card' => 'Карта',
      _ => value,
    };

class _EnglishRoadmapScreen extends StatefulWidget {
  const _EnglishRoadmapScreen({
    required this.database,
    required this.manager,
    required this.targetLanguage,
    required this.languageProfile,
    required this.onCapture,
    required this.onChanged,
  });

  final LocalDatabase database;
  final SessionManager manager;
  final String targetLanguage;
  final Map<String, dynamic> languageProfile;
  final VoidCallback onCapture;
  final VoidCallback onChanged;

  @override
  State<_EnglishRoadmapScreen> createState() => _EnglishRoadmapScreenState();
}

class _EnglishRoadmapScreenState extends State<_EnglishRoadmapScreen> {
  EnglishLesson? _selectedLesson;
  EnglishLearningProfile? _profile;
  bool _editingProfile = false;

  LocalDatabase get database => widget.database;

  @override
  void initState() {
    super.initState();
    final raw = database.englishLearningProfileJson();
    if (raw == null) {
      _profile = _profileFromWorkspace();
      unawaited(database
          .saveEnglishLearningProfileJson(jsonEncode(_profile!.toJson())));
      return;
    }
    try {
      _profile = EnglishLearningProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // A damaged optional intake must never make the lesson path unavailable.
      _profile = _profileFromWorkspace();
    }
  }

  EnglishLearningProfile _profileFromWorkspace() {
    final goalText =
        widget.languageProfile['goal'] as String? ?? 'Свободно общаться';
    final level = widget.languageProfile['currentLevel'] as String? ?? '';
    final weeks = (widget.languageProfile['weeks'] as num?)?.toInt() ?? 12;
    final goal = switch (goalText) {
      'Работа и карьера' => EnglishGoal.work,
      'Переезд' => EnglishGoal.relocation,
      'Путешествия' => EnglishGoal.travel,
      'Экзамен' => EnglishGoal.exam,
      'Свободно общаться' => EnglishGoal.conversation,
      _ => EnglishGoal.study,
    };
    final length = switch (weeks) {
      6 => EnglishCourseLength.sixWeeks,
      24 => EnglishCourseLength.twentyFourWeeks,
      36 => EnglishCourseLength.thirtySixWeeks,
      _ => EnglishCourseLength.twelveWeeks,
    };
    final placement = switch (level) {
      'Начинаю с нуля' => EnglishPlacementBand.a1ToA2,
      'Уверенно общаюсь' => EnglishPlacementBand.b1ToB2,
      _ => EnglishPlacementBand.a2ToB1,
    };
    return EnglishLearningProfile(
      goal: goal,
      courseLength: length,
      intensity: EnglishIntensity.steady,
      placement: placement,
      grammarReadingScore: 0,
      listeningSelfReport: 'ещё не проверено',
      speakingSelfReport: 'ещё не проверено',
      preferredFormats: const [],
      createdAt: DateTime.now(),
      goalNarrative: goalText,
      intakeFacts: {
        'purpose': goalText,
        'startingLevel': level,
      },
      missingFacts: const ['speaking', 'listening'],
      aiSummary:
          'Стартовый план создан по настройкам курса. Его можно уточнить позже.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish =
        widget.targetLanguage.trim().toLowerCase().startsWith('анг');
    final startsFromZero =
        widget.languageProfile['currentLevel'] == 'Начинаю с нуля';
    if (!isEnglish || startsFromZero) {
      return _AiLanguageRoadmapScreen(
        database: database,
        manager: widget.manager,
        targetLanguage: widget.targetLanguage,
        profile: widget.languageProfile,
      );
    }
    if (_profile == null || _editingProfile) {
      return _EnglishIntakeChat(
        database: database,
        manager: widget.manager,
        initial: _editingProfile ? _profile : null,
        onCancel: _editingProfile
            ? () => setState(() => _editingProfile = false)
            : null,
        onSaved: (profile) => setState(() {
          _profile = profile;
          _editingProfile = false;
        }),
      );
    }
    final profile = _profile!;
    final roadmap = buildEnglishRoadmap();
    final completed = database.completedEnglishLessons();
    final a2 = roadmap.forStage(EnglishStage.a2ToB1);
    final b1 = roadmap.forStage(EnglishStage.b1ToB2);
    final a2Complete = a2.every((lesson) => completed.contains(lesson.id));
    if (_selectedLesson != null) {
      return _EnglishLessonDetail(
        lesson: _selectedLesson!,
        database: database,
        onBack: () => setState(() => _selectedLesson = null),
        onCompleted: () {
          setState(() => _selectedLesson = null);
          widget.onChanged();
        },
      );
    }
    final active = [...a2, if (a2Complete) ...b1].firstWhere(
      (lesson) => !completed.contains(lesson.id),
      orElse: () => a2.last,
    );

    return _PageScroll(
      child: ConstrainedBox(
        constraints: const BoxConstraints(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              eyebrow: 'ЯЗЫКОВОЙ КУРС / АНГЛИЙСКИЙ',
              title: 'Ваш путь в английском',
              description:
                  'Короткие занятия в понятной последовательности: база, разговорная практика, понимание речи и постепенное усложнение.',
              trailing: _ModuleIcon(icon: Icons.menu_book_outlined),
            ),
            const SizedBox(height: 24),
            _EnglishPathSummary(
              roadmap: roadmap,
              completed: completed,
              active: active,
              onCapture: widget.onCapture,
              onOpen: () => setState(() => _selectedLesson = active),
            ),
            const SizedBox(height: 20),
            _EnglishProfilePanel(
              profile: profile,
              onEdit: () => setState(() => _editingProfile = true),
            ),
            const SizedBox(height: 20),
            _EnglishStageCard(
              stage: EnglishStage.a2ToB1,
              lessons: a2,
              completed: completed,
              unlocked: true,
              onOpen: (lesson) => setState(() => _selectedLesson = lesson),
            ),
            const SizedBox(height: 12),
            _EnglishStageCard(
              stage: EnglishStage.b1ToB2,
              lessons: b1,
              completed: completed,
              unlocked: a2Complete,
              onOpen: a2Complete
                  ? (lesson) => setState(() => _selectedLesson = lesson)
                  : null,
            ),
            const SizedBox(height: 16),
            _AiExtensionNote(),
          ],
        ),
      ),
    );
  }
}

class _AiLanguageRoadmapScreen extends StatefulWidget {
  const _AiLanguageRoadmapScreen({
    required this.database,
    required this.manager,
    required this.targetLanguage,
    required this.profile,
  });

  final LocalDatabase database;
  final SessionManager manager;
  final String targetLanguage;
  final Map<String, dynamic> profile;

  @override
  State<_AiLanguageRoadmapScreen> createState() =>
      _AiLanguageRoadmapScreenState();
}

class _AiLanguageRoadmapScreenState extends State<_AiLanguageRoadmapScreen> {
  Map<String, dynamic>? roadmap;
  final Set<int> completedDays = {};
  int? diagnosticScore;
  bool busy = false;
  String? error;

  String get preferenceKey =>
      'language.roadmap.${widget.targetLanguage.trim().toLowerCase()}';
  String get completedKey =>
      'language.completed.${widget.targetLanguage.trim().toLowerCase()}';
  String get diagnosticKey =>
      'language.diagnostic.${widget.targetLanguage.trim().toLowerCase()}';

  @override
  void initState() {
    super.initState();
    final saved = widget.database.preference(preferenceKey);
    roadmap =
        saved is Map ? Map<String, dynamic>.from(saved) : _starterRoadmap();
    final savedCompleted = widget.database.preference(completedKey);
    if (savedCompleted is List) {
      completedDays.addAll(
          savedCompleted.whereType<num>().map((value) => value.toInt()));
    }
    final savedDiagnostic = widget.database.preference(diagnosticKey);
    if (savedDiagnostic is Map) {
      diagnosticScore = (savedDiagnostic['score'] as num?)?.toInt();
    }
  }

  String get diagnosticLabel => switch (diagnosticScore) {
        0 || 1 => 'Нужна спокойная база с нуля',
        2 => 'База уже есть — добавим больше коротких диалогов',
        3 => 'Можно быстрее переходить к живым ситуациям',
        4 => 'Стартовый уровень уверенный — нужен сложный материал',
        _ => 'Пройдите короткую самопроверку перед первым занятием',
      };

  Future<void> _openDiagnostic() async {
    final selected = <int>{};
    final saved = widget.database.preference(diagnosticKey);
    if (saved is Map && saved['checks'] is List) {
      selected.addAll((saved['checks'] as List)
          .whereType<num>()
          .map((value) => value.toInt()));
    }
    final checks = [
      'Могу поздороваться и представиться одной-двумя фразами.',
      'Понимаю медленный короткий вопрос о себе, времени или месте.',
      'Могу рассказать о себе минимум тремя простыми предложениями.',
      'Понимаю основной смысл короткого сообщения без перевода каждого слова.',
    ];
    final approved = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, updateDialog) => AlertDialog(
              title: Text('Быстрая диагностика: ${widget.targetLanguage}'),
              content: SizedBox(
                width: 580,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Отметьте только то, что можете сделать сейчас без переводчика. Это не экзамен и не официальный уровень — результат нужен для темпа первых занятий.',
                    ),
                    const SizedBox(height: 12),
                    ...checks.asMap().entries.map(
                          (entry) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: selected.contains(entry.key),
                            title: Text(entry.value),
                            onChanged: (value) => updateDialog(() {
                              value == true
                                  ? selected.add(entry.key)
                                  : selected.remove(entry.key);
                            }),
                          ),
                        ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Не сейчас'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Сохранить результат'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!approved) return;
    await widget.database.savePreference(diagnosticKey, {
      'score': selected.length,
      'checks': selected.toList()..sort(),
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });
    if (mounted) setState(() => diagnosticScore = selected.length);
  }

  Future<void> _setCompleted(int day, bool value) async {
    setState(() => value ? completedDays.add(day) : completedDays.remove(day));
    await widget.database.savePreference(
      completedKey,
      completedDays.toList()..sort(),
    );
  }

  Map<String, dynamic> _starterRoadmap() {
    final weeks = (widget.profile['weeks'] as num?)?.toInt() ?? 12;
    final first = (weeks / 3).ceil();
    return {
      'title': 'Стартовый план: ${widget.targetLanguage}',
      'summary':
          'Начните с коротких занятий и живых ситуаций. План уже работает без ожидания; позже его можно уточнить под ваш прогресс.',
      'phases': [
        {
          'weeks': '1–$first',
          'focus': 'База для ежедневных ситуаций',
          'outcome': 'Приветствие, знакомство, числа и простые вопросы.',
        },
        {
          'weeks': '${first + 1}–${first * 2}',
          'focus': 'Понимание и короткий диалог',
          'outcome': 'Фразы для вашей цели и регулярная практика слуха.',
        },
        {
          'weeks': '${first * 2 + 1}–$weeks',
          'focus': 'Уверенность в реальных сценариях',
          'outcome': 'Больше самостоятельной речи и разбор слабых мест.',
        },
      ],
      'starterLessons': [
        {
          'day': 1,
          'title': 'Первое знакомство',
          'task': 'Выучите 8 базовых фраз и произнесите их вслух.',
          'minutes': 20,
        },
        {
          'day': 2,
          'title': 'Слушаем и повторяем',
          'task': 'Послушайте короткий диалог и повторите ключевые фразы.',
          'minutes': 25,
        },
        {
          'day': 3,
          'title': 'Мини-диалог',
          'task': 'Составьте пять реплик о себе и своей цели.',
          'minutes': 25,
        },
      ],
      'starter': true,
    };
  }

  Future<void> _generate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.manager.authenticatedRequest(
        'POST',
        '/api/ai/language-roadmap',
        body: {
          'targetLanguage': widget.targetLanguage,
          'nativeLanguage': 'Русский',
          'goal': widget.profile['goal'] ?? 'Свободно общаться',
          'currentLevel': widget.profile['currentLevel'] ?? 'Начинаю с нуля',
          'weeks': widget.profile['weeks'] ?? 12,
          'minutesPerWeek': 180,
          'diagnosticScore': diagnosticScore,
          'completedStarterDays': completedDays.toList()..sort(),
        },
      );
      if (result is! Map) throw const ApiFailure('request_failed');
      final value = Map<String, dynamic>.from(result);
      await widget.database.savePreference(preferenceKey, value);
      if (mounted) setState(() => roadmap = value);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phases =
        roadmap?['phases'] is List ? roadmap!['phases'] as List : const [];
    final lessons = roadmap?['starterLessons'] is List
        ? roadmap!['starterLessons'] as List
        : const [];
    final firstLesson = lessons.whereType<Map>().isEmpty
        ? null
        : Map<String, dynamic>.from(lessons.whereType<Map>().first);
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            eyebrow: 'ЯЗЫКОВОЙ КУРС / ${widget.targetLanguage.toUpperCase()}',
            title: 'Курс: ${widget.targetLanguage}',
            description:
                'План строится под вашу цель, стартовый уровень и доступное время. Его можно пересобрать, когда обстоятельства изменятся.',
            trailing: const _ModuleIcon(icon: Icons.translate_rounded),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TinyChip(
                  label: (widget.profile['goal'] as String? ?? 'Практика')
                      .toUpperCase()),
              _TinyChip(
                  label: (widget.profile['currentLevel'] as String? ??
                          'Стартовый уровень')
                      .toUpperCase()),
              _TinyChip(label: '${widget.profile['weeks'] ?? 12} НЕДЕЛЬ'),
            ],
          ),
          const SizedBox(height: 12),
          _HoverPanel(
            color: _elevated,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined, color: _amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Проверка стартовой точки',
                          style: TextStyle(
                              color: _primary, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(diagnosticLabel,
                          style: TextStyle(
                              color: _secondary, fontSize: 12, height: 1.4)),
                      const SizedBox(height: 3),
                      Text(
                        'История этого языка хранится отдельно и не исчезнет при переключении курса.',
                        style: TextStyle(color: _tertiary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: _openDiagnostic,
                  child: Text(diagnosticScore == null ? 'Пройти' : 'Повторить'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (roadmap == null)
            _HoverPanel(
              borderColor: _amberLine,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _PanelKicker(
                      icon: Icons.route_outlined,
                      label: 'ПЕРСОНАЛЬНЫЙ ROADMAP'),
                  const SizedBox(height: 12),
                  Text('Сначала создадим реалистичный маршрут',
                      style: TextStyle(
                          color: _primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'AI подготовит этапы и первые занятия. Это рабочий план, а не обещание уровня или результата экзамена.',
                    style: TextStyle(color: _secondary, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy ? null : _generate,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(busy ? 'Строим план…' : 'Создать мой roadmap'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    _NoticeBanner(message: error!),
                  ],
                ],
              ),
            )
          else ...[
            _HoverPanel(
              borderColor: _amberLine,
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.flag_outlined, color: _amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            roadmap?['title'] as String? ??
                                'Персональный языковой план',
                            style: TextStyle(
                                color: _primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(roadmap?['summary'] as String? ?? '',
                            style: TextStyle(color: _secondary, height: 1.45)),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : _generate,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(busy ? 'Уточняем…' : 'Уточнить план'),
                  ),
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              const _NoticeBanner(
                message:
                    'Не удалось уточнить план через интернет. Стартовый курс остаётся доступен, данные не потеряны.',
              ),
            ],
            if (firstLesson != null) ...[
              const SizedBox(height: 12),
              _HoverPanel(
                borderColor: _amberLine,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _amber.withAlpha(24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('1',
                          style: TextStyle(
                              color: _amber, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Начните сегодня',
                              style: TextStyle(
                                  color: _tertiary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(firstLesson['title'] as String? ?? 'Занятие',
                              style: TextStyle(
                                  color: _primary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(
                              '${firstLesson['task'] as String? ?? ''} · ${firstLesson['minutes'] ?? 20} минут',
                              style:
                                  TextStyle(color: _secondary, fontSize: 12)),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () =>
                          _setCompleted(1, !completedDays.contains(1)),
                      icon: Icon(completedDays.contains(1)
                          ? Icons.check_rounded
                          : Icons.play_arrow_rounded),
                      label: Text(
                          completedDays.contains(1) ? 'Выполнено' : 'Отметить'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            const _SectionHeader(
                eyebrow: 'ЭТАПЫ', title: 'Как будет расти навык'),
            const SizedBox(height: 10),
            ...phases.whereType<Map>().map((raw) {
              final phase = Map<String, dynamic>.from(raw);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HoverPanel(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _amber.withAlpha(22),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text('${phase['weeks'] ?? '—'}',
                              style: TextStyle(
                                  color: _amber, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(phase['focus'] as String? ?? 'Практика',
                                style: TextStyle(
                                    color: _primary,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(phase['outcome'] as String? ?? '',
                                style:
                                    TextStyle(color: _secondary, height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (lessons.isNotEmpty) ...[
              const SizedBox(height: 12),
              const _SectionHeader(eyebrow: 'СТАРТ', title: 'Первые занятия'),
              const SizedBox(height: 10),
              ...lessons.whereType<Map>().map((raw) {
                final lesson = Map<String, dynamic>.from(raw);
                final day = (lesson['day'] as num?)?.toInt() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _HoverPanel(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: CheckboxListTile(
                      value: completedDays.contains(day),
                      onChanged: day == 0
                          ? null
                          : (value) => _setCompleted(day, value ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: _amber,
                      title: Text(lesson['title'] as String? ?? 'Занятие'),
                      subtitle: Text(
                        '${lesson['task'] as String? ?? ''}\n${lesson['minutes'] ?? 30} минут',
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

class _EnglishProfilePanel extends StatelessWidget {
  const _EnglishProfilePanel({required this.profile, required this.onEdit});

  final EnglishLearningProfile profile;
  final VoidCallback onEdit;

  Future<void> _openYoutube(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(profile.youtubeSearchUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть поиск YouTube.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _HoverPanel(
        color: _elevated,
        borderColor: _amberLine,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _PanelKicker(
                    icon: Icons.forum_outlined,
                    label: 'ВАШ ПЛАН И СТАРТОВЫЙ УРОВЕНЬ',
                  ),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('ИЗМЕНИТЬ'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              profile.goalText,
              style: TextStyle(
                color: _primary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              profile.deadlineText.isEmpty
                  ? profile.outcomeBoundary
                  : 'Срок: ${profile.deadlineText}. ${profile.outcomeBoundary}',
              style: TextStyle(color: _secondary, fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (profile.deadlineText.isNotEmpty)
                  _TinyChip(label: profile.deadlineText.toUpperCase()),
                if (profile.intakeFacts['exam']?.isNotEmpty == true)
                  _TinyChip(
                    label: profile.intakeFacts['exam']!.toUpperCase(),
                  ),
                if (profile.preferredFormats.isNotEmpty)
                  _TinyChip(
                    label: profile.preferredFormats.join(' · ').toUpperCase(),
                  ),
                const _TinyChip(label: 'АУДИО И РЕЧЬ — САМООЦЕНКА'),
              ],
            ),
            const SizedBox(height: 12),
            _EnglishBoundaryRow(
              icon: Icons.check_circle_outline,
              title: 'В приложении',
              text: 'план, задания, журнал и локальный прогресс.',
            ),
            _EnglishBoundaryRow(
              icon: Icons.smart_toy_outlined,
              title: 'AI-помощь',
              text:
                  'может объяснить и предложить практику, но не ставит официальный уровень.',
            ),
            _EnglishBoundaryRow(
              icon: Icons.open_in_new,
              title: 'Внешняя проверка',
              text:
                  'аудирование, произношение и экзамены требуют внешнего или человеческого подтверждения.',
            ),
            const SizedBox(height: 11),
            OutlinedButton.icon(
              onPressed: () => _openYoutube(context),
              icon: const Icon(Icons.ondemand_video_outlined, size: 16),
              label: const Text('ОТКРЫТЬ ПОИСК ПРАКТИКИ НА YOUTUBE'),
            ),
            const SizedBox(height: 5),
            Text(
              'Это поиск, а не рекомендация конкретного ролика: приложение не выдаёт непроверенное видео за оценку или урок.',
              style: TextStyle(color: _tertiary, fontSize: 11, height: 1.35),
            ),
          ],
        ),
      );
}

class _EnglishBoundaryRow extends StatelessWidget {
  const _EnglishBoundaryRow({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _amber, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$title: ',
                      style: TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: text),
                  ],
                ),
                style: TextStyle(color: _secondary, fontSize: 11, height: 1.35),
              ),
            ),
          ],
        ),
      );
}

class _EnglishChatMessage {
  const _EnglishChatMessage(this.text, {required this.isUser});

  final String text;
  final bool isUser;
}

class _EnglishIntakeChat extends StatefulWidget {
  const _EnglishIntakeChat({
    required this.database,
    required this.manager,
    required this.initial,
    required this.onSaved,
    this.onCancel,
  });

  final LocalDatabase database;
  final SessionManager manager;
  final EnglishLearningProfile? initial;
  final ValueChanged<EnglishLearningProfile> onSaved;
  final VoidCallback? onCancel;

  @override
  State<_EnglishIntakeChat> createState() => _EnglishIntakeChatState();
}

class _EnglishIntakeChatState extends State<_EnglishIntakeChat> {
  final _controller = TextEditingController();
  final _composerFocus = FocusNode(debugLabel: 'english-chat-composer');
  final List<_EnglishChatMessage> _messages = [];
  Map<String, String> _facts = {};
  List<String> _missing = [];
  bool _busy = false;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _facts = {...?initial?.intakeFacts};
    _messages.add(const _EnglishChatMessage(
      'Для чего вам нужен английский? Расскажите как удобно — можно сразу назвать срок, страну, экзамен, университет или рабочую цель.',
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _sanitizeEnglishChatMessage(_controller.text);
    if (message.isEmpty || _busy) return;
    if (widget.manager.session == null) {
      setState(() => _error =
          'Чтобы начать именно AI-диалог, войдите в свой аккаунт: ключ модели остаётся на сервере.');
      return;
    }
    final history = [
      for (final item in _messages.skip(1))
        {'role': item.isUser ? 'user' : 'assistant', 'content': item.text},
    ];
    setState(() {
      _messages.add(_EnglishChatMessage(message, isUser: true));
      _controller.clear();
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.manager
          .authenticatedRequest('POST', '/api/ai/english-onboarding', body: {
        'message': message,
        'facts': _facts,
        'history': history,
      }) as Map<String, dynamic>;
      final facts = <String, String>{
        for (final entry in (result['facts'] as Map? ?? const {}).entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
      final reply = result['reply'] as String?;
      if (reply == null || reply.trim().isEmpty)
        throw const ApiFailure('ai_request_failed');
      if (!mounted) return;
      setState(() {
        _facts = facts;
        _missing = [
          for (final value in (result['missing'] as List? ?? const []))
            if (value is String) value,
        ];
        _ready = result['ready'] == true;
        _messages.add(_EnglishChatMessage(reply, isUser: false));
      });
    } on ApiFailure catch (value) {
      if (mounted) setState(() => _error = value.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _appendToComposer(String text) {
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : _controller.text.length;
    _controller.value = _controller.value.copyWith(
      text: _controller.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    );
  }

  KeyEventResult _handleChatKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (!_composerFocus.hasFocus) {
          _appendToComposer('\n');
          _composerFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      _send();
      return KeyEventResult.handled;
    }

    if (_composerFocus.hasFocus ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final character = event.character;
    if (character == null ||
        character.isEmpty ||
        character.codeUnitAt(0) < 32) {
      return KeyEventResult.ignored;
    }
    _appendToComposer(character);
    _composerFocus.requestFocus();
    return KeyEventResult.handled;
  }

  Future<void> _save() async {
    if (!_ready || _busy) return;
    final initial = widget.initial;
    final profile = EnglishLearningProfile(
      goal: initial?.goal ?? EnglishGoal.study,
      courseLength: initial?.courseLength ?? EnglishCourseLength.twelveWeeks,
      intensity: initial?.intensity ?? EnglishIntensity.steady,
      placement: initial?.placement ?? EnglishPlacementBand.a2ToB1,
      grammarReadingScore: initial?.grammarReadingScore ?? 0,
      listeningSelfReport: initial?.listeningSelfReport ?? 'не оценено',
      speakingSelfReport: initial?.speakingSelfReport ?? 'не оценено',
      preferredFormats: initial?.preferredFormats ?? const [],
      createdAt: DateTime.now(),
      goalNarrative: _facts['purpose'] ?? initial?.goalNarrative ?? '',
      intakeFacts: _facts,
      missingFacts: _missing,
      aiSummary: _messages.isEmpty ? '' : _messages.last.text,
    );
    await widget.database
        .saveEnglishLearningProfileJson(jsonEncode(profile.toJson()));
    if (mounted) widget.onSaved(profile);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 700;
      return Focus(
        autofocus: true,
        onKeyEvent: _handleChatKey,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              narrow ? 12 : 28, 14, narrow ? 12 : 28, narrow ? 10 : 18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _PageHeader(
              eyebrow: 'АНГЛИЙСКИЙ / УТОЧНЕНИЕ ПЛАНА',
              title: 'Уточним курс под вашу ситуацию.',
              description:
                  'Ответьте своими словами: зачем нужен язык, какой срок важен и что уже получается. Изменения сохранятся только после подтверждения.',
              trailing: _ModuleIcon(icon: Icons.forum_outlined),
            ),
            const SizedBox(height: 12),
            Expanded(
                child: _HoverPanel(
              color: Colors.transparent,
              borderColor: _amberLine,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.onCancel != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: widget.onCancel,
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('ОТМЕНИТЬ ИЗМЕНЕНИЯ'),
                      ),
                    ),
                  Expanded(
                      child: ListView(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    children: [
                      for (final message in _messages)
                        _EnglishChatBubble(message: message),
                      if (_error != null) _NoticeBanner(message: _error!),
                      if (_ready)
                        _EnglishReadyPanel(facts: _facts, onSave: _save),
                    ],
                  )),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                        child: SizedBox(
                      height: 48,
                      child: TextField(
                        controller: _controller,
                        focusNode: _composerFocus,
                        enabled: !_busy,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            prefixIconConstraints:
                                BoxConstraints(minWidth: 44, minHeight: 36),
                            prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                            hintText:
                                'Например: хочу поступить в Германию через 8 месяцев, IELTS ещё не сдавал'),
                      ),
                    )),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _send,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send, size: 16),
                        label: Text(_busy ? 'AI АНАЛИЗИРУЕТ…' : 'ОТПРАВИТЬ'),
                      ),
                    ),
                  ]),
                ],
              ),
            )),
          ]),
        ),
      );
    });
  }
}

String _sanitizeEnglishChatMessage(String raw) {
  final cleaned = <String>[];
  var emptyLines = 0;
  for (final rawLine in raw.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) {
      emptyLines += 1;
      if (emptyLines > 3) break;
      cleaned.add('');
    } else {
      emptyLines = 0;
      cleaned.add(line);
    }
  }
  while (cleaned.isNotEmpty && cleaned.first.isEmpty) {
    cleaned.removeAt(0);
  }
  while (cleaned.isNotEmpty && cleaned.last.isEmpty) {
    cleaned.removeLast();
  }
  return cleaned.join('\n');
}

class _EnglishChatBubble extends StatelessWidget {
  const _EnglishChatBubble({required this.message});
  final _EnglishChatMessage message;

  @override
  Widget build(BuildContext context) => Align(
        alignment:
            message.isUser ? const Alignment(0.58, 0) : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 610),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: message.isUser ? _amber.withValues(alpha: 0.13) : _surface,
            border: Border.all(color: message.isUser ? _amberLine : _line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            message.text,
            style: TextStyle(
                color: message.isUser ? _primary : _secondary,
                fontSize: 13,
                height: 1.35),
          ),
        ),
      );
}

class _EnglishOptionWrap extends StatelessWidget {
  const _EnglishOptionWrap({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: children,
      );
}

class _EnglishProposal extends StatelessWidget {
  const _EnglishProposal({
    required this.profile,
    required this.saving,
    required this.onSave,
  });

  final EnglishLearningProfile profile;
  final bool saving;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _recessed,
          border: Border.all(color: _amberLine),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ВАШ СТАРТОВЫЙ ПЛАН',
                style: TextStyle(
                    color: _amber,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 10,
                    letterSpacing: .6)),
            const SizedBox(height: 8),
            Text('${profile.placement.label} · ${profile.goal.label}',
                style: TextStyle(
                    color: _primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(profile.workload,
                style: TextStyle(color: _secondary, fontSize: 13)),
            const SizedBox(height: 5),
            Text(profile.outcomeBoundary,
                style: TextStyle(color: _secondary, fontSize: 12, height: 1.4)),
            const SizedBox(height: 8),
            Text(profile.confidenceNote,
                style: TextStyle(color: _tertiary, fontSize: 11, height: 1.35)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check, size: 16),
              label:
                  Text(saving ? 'СОХРАНЯЕМ...' : 'СОХРАНИТЬ И ОТКРЫТЬ УРОКИ'),
            ),
          ],
        ),
      );
}

class _EnglishReadyPanel extends StatelessWidget {
  const _EnglishReadyPanel({required this.facts, required this.onSave});

  final Map<String, String> facts;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _recessed,
          border: Border.all(color: _amberLine),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('КОНТЕКСТ СОБРАН',
                style: TextStyle(
                    color: _amber,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 10,
                    letterSpacing: .6)),
            const SizedBox(height: 8),
            Text(facts['purpose'] ?? 'Цель английского',
                style: TextStyle(
                    color: _primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            if (facts['deadline']?.isNotEmpty == true) ...[
              const SizedBox(height: 5),
              Text('Срок: ${facts['deadline']}',
                  style: TextStyle(color: _secondary, fontSize: 13)),
            ],
            if (facts['exam']?.isNotEmpty == true)
              Text('Экзамен: ${facts['exam']}',
                  style: TextStyle(color: _secondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text(
                'Это контекст для плана, не обещание поступления, балла экзамена или уровня языка.',
                style: TextStyle(color: _tertiary, fontSize: 11, height: 1.35)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('СОХРАНИТЬ И ОТКРЫТЬ УРОКИ'),
            ),
          ],
        ),
      );
}

class _EnglishPathSummary extends StatelessWidget {
  const _EnglishPathSummary({
    required this.roadmap,
    required this.completed,
    required this.active,
    required this.onCapture,
    required this.onOpen,
  });

  final EnglishRoadmap roadmap;
  final Set<String> completed;
  final EnglishLesson active;
  final VoidCallback onCapture;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final completedCount =
        roadmap.lessons.where((lesson) => completed.contains(lesson.id)).length;
    final percentage = completedCount / roadmap.lessons.length;
    return _HoverPanel(
      borderColor: _amberLine,
      glowOnHover: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PanelKicker(
                  icon: Icons.route_outlined,
                  label: 'ПОШАГОВЫЙ КУРС · 174 ЗАНЯТИЯ',
                ),
              ),
              OutlinedButton.icon(
                onPressed: onCapture,
                icon: Icon(Icons.bolt, size: 16),
                label: Text('БЫСТРАЯ ЗАПИСЬ'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$completedCount',
                style: TextStyle(
                  color: _primary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 5, left: 6),
                child: Text(
                  '/ 174 занятий завершено',
                  style: TextStyle(color: _secondary, fontSize: 13),
                ),
              ),
              const Spacer(),
              Text(
                '${(percentage * 100).round()}%',
                style: TextStyle(
                  color: _amber,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 6,
              backgroundColor: _elevated,
              color: _amber,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _elevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                Icon(Icons.play_arrow_rounded, color: _amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'СЛЕДУЮЩЕЕ ЗАНЯТИЕ',
                        style: TextStyle(
                          color: _tertiary,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 9,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${active.stage.title} · неделя ${active.week}, день ${active.day}',
                        style: TextStyle(
                          color: _amber,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active.title,
                        style: TextStyle(
                          color: _primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        active.objective,
                        style: TextStyle(
                          color: _secondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: Text('Начать · ${active.estimatedMinutes} мин'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EnglishStageCard extends StatelessWidget {
  const _EnglishStageCard({
    required this.stage,
    required this.lessons,
    required this.completed,
    required this.unlocked,
    required this.onOpen,
  });

  final EnglishStage stage;
  final List<EnglishLesson> lessons;
  final Set<String> completed;
  final bool unlocked;
  final ValueChanged<EnglishLesson>? onOpen;

  @override
  Widget build(BuildContext context) {
    final done =
        lessons.where((lesson) => completed.contains(lesson.id)).length;
    final weeks = <int, List<EnglishLesson>>{};
    for (final lesson in lessons) {
      weeks.putIfAbsent(lesson.week, () => []).add(lesson);
    }
    return _HoverPanel(
      color: _surface,
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: stage == EnglishStage.a2ToB1 && unlocked,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: _amber,
          collapsedIconColor: _tertiary,
          title: Row(
            children: [
              _StageBadge(stage: stage),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stage.title,
                      style: TextStyle(
                        color: _primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stage.description,
                      style: TextStyle(color: _secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '$done / ${lessons.length}',
                style: TextStyle(
                  color: _amber,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 11,
                ),
              ),
            ],
          ),
          children: [
            if (!unlocked)
              _LockedStageNotice()
            else
              for (final entry in weeks.entries)
                _EnglishWeekGroup(
                  week: entry.key,
                  lessons: entry.value,
                  completed: completed,
                  onOpen: onOpen,
                ),
          ],
        ),
      ),
    );
  }
}

class _EnglishWeekGroup extends StatelessWidget {
  const _EnglishWeekGroup({
    required this.week,
    required this.lessons,
    required this.completed,
    required this.onOpen,
  });

  final int week;
  final List<EnglishLesson> lessons;
  final Set<String> completed;
  final ValueChanged<EnglishLesson>? onOpen;

  @override
  Widget build(BuildContext context) {
    final done =
        lessons.where((lesson) => completed.contains(lesson.id)).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _recessed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 7),
            child: Row(
              children: [
                Text(
                  'WEEK ${week.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: _amber,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    lessons.first.title,
                    style: TextStyle(color: _secondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$done / ${lessons.length}',
                  style: TextStyle(
                    color: _tertiary,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          for (final lesson in lessons)
            _EnglishLessonRow(
              lesson: lesson,
              completed: completed.contains(lesson.id),
              onOpen: onOpen == null ? null : () => onOpen!(lesson),
            ),
        ],
      ),
    );
  }
}

class _EnglishLessonRow extends StatelessWidget {
  const _EnglishLessonRow({
    required this.lesson,
    required this.completed,
    required this.onOpen,
  });

  final EnglishLesson lesson;
  final bool completed;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onOpen,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: _line)),
          ),
          child: Row(
            children: [
              Icon(
                completed
                    ? Icons.check_circle_rounded
                    : Icons.play_circle_outline_rounded,
                color: completed ? _green : _amber,
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'DAY ${lesson.day.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: _tertiary,
                            fontFamily: 'Cascadia Mono',
                            fontSize: 9,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _LessonKindChip(kind: lesson.kind),
                        if (lesson.checkpoint) ...[
                          const SizedBox(width: 6),
                          _TinyChip(label: 'CHECKPOINT'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lesson.title,
                      style: TextStyle(
                        color: completed ? _tertiary : _primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration:
                            completed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        for (final block in lesson.blocks)
                          _TinyChip(label: block.skill.label.toUpperCase()),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${lesson.estimatedMinutes}m',
                    style: TextStyle(
                      color: _secondary,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Icon(Icons.chevron_right, color: _tertiary, size: 16),
                ],
              ),
            ],
          ),
        ),
      );
}

class _LockedStageNotice extends StatelessWidget {
  const _LockedStageNotice();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 4),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _amberLine),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: _amber, size: 21),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'B2 откроется после завершения всех 90 уроков A2.5 → B1. Сначала закрепим рабочий B1, затем добавим сложность.',
                style: TextStyle(color: _secondary, fontSize: 12, height: 1.45),
              ),
            ),
          ],
        ),
      );
}

class _EnglishLessonDetail extends StatefulWidget {
  const _EnglishLessonDetail({
    required this.lesson,
    required this.database,
    required this.onBack,
    required this.onCompleted,
  });

  final EnglishLesson lesson;
  final LocalDatabase database;
  final VoidCallback onBack;
  final VoidCallback onCompleted;

  @override
  State<_EnglishLessonDetail> createState() => _EnglishLessonDetailState();
}

class _EnglishLessonDetailState extends State<_EnglishLessonDetail> {
  late EnglishLessonProgress _progress;
  late final TextEditingController _writingController;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _recording = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _progress = widget.database.englishLessonProgress(widget.lesson.id);
    _writingController = TextEditingController(text: _progress.writingText);
  }

  @override
  void dispose() {
    _writingController.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _persist({
    bool? readingDone,
    bool? listeningDone,
    String? writingText,
    String? speakingPath,
  }) async {
    final next = EnglishLessonProgress(
      readingDone: readingDone ?? _progress.readingDone,
      listeningDone: listeningDone ?? _progress.listeningDone,
      writingText: writingText ?? _progress.writingText,
      speakingPath: speakingPath ?? _progress.speakingPath,
    );
    await widget.database.saveEnglishLessonProgress(
      widget.lesson.id,
      readingDone: next.readingDone,
      listeningDone: next.listeningDone,
      writingText: next.writingText,
      speakingPath: next.speakingPath,
    );
    if (!next.allSkillsDone) {
      await widget.database.setEnglishLessonCompleted(widget.lesson.id, false);
    }
    if (!mounted) return;
    setState(() {
      _progress = next;
      _error = null;
    });
  }

  Future<void> _openListening(EnglishLessonBlock block) async {
    final url = block.url;
    if (url == null) return;
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      if (mounted) setState(() => _error = 'Не удалось открыть YouTube.');
      return;
    }
    await _persist(listeningDone: true);
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (path != null) await _persist(speakingPath: path);
      return;
    }
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() => _error = 'Нет разрешения на использование микрофона.');
      }
      return;
    }
    final directory = await widget.database.attachmentDirectory(
      'english-recordings',
    );
    final path = p.join(
      directory.path,
      'english_${widget.lesson.id}_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _saveWriting() async {
    if (_writingController.text.trim().isEmpty) {
      setState(() => _error = 'Добавь хотя бы короткий письменный ответ.');
      return;
    }
    setState(() => _saving = true);
    await _persist(writingText: _writingController.text.trim());
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _finishLesson() async {
    if (!_progress.allSkillsDone) return;
    await widget.database.setEnglishLessonCompleted(widget.lesson.id, true);
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final reading = widget.lesson.blocks.firstWhere(
      (block) => block.skill == EnglishSkill.reading,
    );
    final listening = widget.lesson.blocks.firstWhere(
      (block) => block.skill == EnglishSkill.listening,
    );
    final speaking = widget.lesson.blocks.firstWhere(
      (block) => block.skill == EnglishSkill.speaking,
    );
    final writing = widget.lesson.blocks.firstWhere(
      (block) => block.skill == EnglishSkill.writing,
    );
    final doneCount = [
      _progress.readingDone,
      _progress.listeningDone,
      _progress.speakingPath != null,
      _progress.writingText.trim().isNotEmpty,
    ].where((done) => done).length;

    return _PageScroll(
      child: ConstrainedBox(
        constraints: const BoxConstraints(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: Icon(Icons.arrow_back, size: 17),
              label: Text('К ПЛАНУ КУРСА'),
              style: TextButton.styleFrom(foregroundColor: _secondary),
            ),
            const SizedBox(height: 8),
            _PageHeader(
              eyebrow:
                  '${widget.lesson.stage.title} / НЕДЕЛЯ ${widget.lesson.week.toString().padLeft(2, '0')} / ДЕНЬ ${widget.lesson.day.toString().padLeft(2, '0')}',
              title: widget.lesson.title,
              description: widget.lesson.objective,
              trailing: _StageBadge(stage: widget.lesson.stage),
            ),
            const SizedBox(height: 18),
            _EnglishLessonProgressHeader(
              lesson: widget.lesson,
              doneCount: doneCount,
              canFinish: _progress.allSkillsDone,
              onFinish: _finishLesson,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _NoticeBanner(message: _error!),
            ],
            const SizedBox(height: 16),
            _EnglishSkillCard(
              block: reading,
              done: _progress.readingDone,
              onDoneChanged: (value) => _persist(readingDone: value),
            ),
            const SizedBox(height: 10),
            _EnglishSkillCard(
              block: listening,
              done: _progress.listeningDone,
              onDoneChanged: (value) => _persist(listeningDone: value),
              onOpen: () => _openListening(listening),
            ),
            const SizedBox(height: 10),
            _EnglishSkillCard(
              block: speaking,
              done: _progress.speakingPath != null,
              recording: _recording,
              recordedPath: _progress.speakingPath,
              onRecord: _toggleRecording,
              onPlay: _progress.speakingPath == null
                  ? null
                  : () => _player.play(
                        DeviceFileSource(_progress.speakingPath!),
                      ),
            ),
            const SizedBox(height: 10),
            _EnglishSkillCard(
              block: writing,
              done: _progress.writingText.trim().isNotEmpty,
              writingController: _writingController,
              saving: _saving,
              onSaveWriting: _saveWriting,
            ),
            const SizedBox(height: 18),
            _AiExtensionNote(),
          ],
        ),
      ),
    );
  }
}

class _EnglishLessonProgressHeader extends StatelessWidget {
  const _EnglishLessonProgressHeader({
    required this.lesson,
    required this.doneCount,
    required this.canFinish,
    required this.onFinish,
  });

  final EnglishLesson lesson;
  final int doneCount;
  final bool canFinish;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) => _HoverPanel(
        borderColor: _amberLine,
        glowOnHover: true,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PanelKicker(
                    icon: Icons.timer_outlined,
                    label: 'ОДНО ЗАНЯТИЕ · ЧЕТЫРЕ НАВЫКА',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$doneCount из 4 блоков завершено · ${lesson.estimatedMinutes} минут',
                    style: TextStyle(color: _primary, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Чтение → аудирование → речь → письмо. Занятие закрывается после практики всех четырёх навыков.',
                    style: TextStyle(
                        color: _secondary, fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: canFinish ? onFinish : null,
              icon: Icon(Icons.check, size: 17),
              label: Text('ЗАВЕРШИТЬ ЗАНЯТИЕ'),
            ),
          ],
        ),
      );
}

class _EnglishSkillCard extends StatelessWidget {
  const _EnglishSkillCard({
    required this.block,
    required this.done,
    this.onDoneChanged,
    this.onOpen,
    this.onRecord,
    this.onPlay,
    this.recording = false,
    this.recordedPath,
    this.writingController,
    this.saving = false,
    this.onSaveWriting,
  });

  final EnglishLessonBlock block;
  final bool done;
  final ValueChanged<bool>? onDoneChanged;
  final VoidCallback? onOpen;
  final VoidCallback? onRecord;
  final VoidCallback? onPlay;
  final bool recording;
  final String? recordedPath;
  final TextEditingController? writingController;
  final bool saving;
  final VoidCallback? onSaveWriting;

  @override
  Widget build(BuildContext context) {
    final icon = switch (block.skill) {
      EnglishSkill.reading => Icons.menu_book_outlined,
      EnglishSkill.writing => Icons.edit_note_outlined,
      EnglishSkill.listening => Icons.headphones_outlined,
      EnglishSkill.speaking => Icons.mic_none_outlined,
    };
    final skillLabel = switch (block.skill) {
      EnglishSkill.reading => 'ЧТЕНИЕ',
      EnglishSkill.writing => 'ПИСЬМО',
      EnglishSkill.listening => 'АУДИРОВАНИЕ',
      EnglishSkill.speaking => 'РЕЧЬ',
    };
    return _HoverPanel(
      color: _surface,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _amber, size: 19),
              const SizedBox(width: 9),
              Text(
                skillLabel,
                style: TextStyle(
                  color: _amber,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              _TinyChip(label: '${block.minutes} МИН'),
              const SizedBox(width: 8),
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? _green : _tertiary,
                size: 19,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            block.title,
            style: TextStyle(
              color: _primary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            block.instruction,
            style: TextStyle(color: _secondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _elevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Text(
              block.content,
              style: TextStyle(color: _primary, fontSize: 13, height: 1.5),
            ),
          ),
          if (block.skill == EnglishSkill.listening && onOpen != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: Icon(Icons.open_in_new, size: 16),
              label: Text('ОТКРЫТЬ МАТЕРИАЛ НА YOUTUBE'),
            ),
          ],
          if (block.skill == EnglishSkill.speaking && onRecord != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onRecord,
                  icon: Icon(recording ? Icons.stop : Icons.mic, size: 17),
                  label:
                      Text(recording ? 'ОСТАНОВИТЬ ЗАПИСЬ' : 'ЗАПИСАТЬ РЕЧЬ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: recording ? _red : _amber,
                  ),
                ),
                if (recordedPath != null && onPlay != null) ...[
                  const SizedBox(width: 9),
                  OutlinedButton.icon(
                    onPressed: onPlay,
                    icon: Icon(Icons.play_arrow, size: 17),
                    label: Text('ПРОСЛУШАТЬ'),
                  ),
                ],
              ],
            ),
          ],
          if (block.skill == EnglishSkill.writing &&
              writingController != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: writingController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Напиши свой ответ на английском...',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: saving ? null : onSaveWriting,
              icon: Icon(Icons.save_outlined, size: 17),
              label: Text(saving ? 'СОХРАНЯЕМ…' : 'СОХРАНИТЬ ОТВЕТ'),
            ),
          ],
          if (block.skill == EnglishSkill.reading && onDoneChanged != null) ...[
            const SizedBox(height: 10),
            CheckboxListTile(
              value: done,
              onChanged: (value) => onDoneChanged!(value ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: _amber,
              checkColor: _base,
              title: Text('Я прочитал и отметил новые фразы'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
          if (block.skill == EnglishSkill.listening &&
              onDoneChanged != null) ...[
            const SizedBox(height: 10),
            CheckboxListTile(
              value: done,
              onChanged: (value) => onDoneChanged!(value ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: _amber,
              checkColor: _base,
              title: Text('Я прослушал материал и пересказал смысл'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ],
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.stage});

  final EnglishStage stage;

  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _amber.withAlpha(18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _amberLine),
        ),
        child: Text(
          stage == EnglishStage.a2ToB1 ? 'B1' : 'B2',
          style: TextStyle(
            color: _amber,
            fontFamily: 'Cascadia Mono',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _LessonKindChip extends StatelessWidget {
  const _LessonKindChip({required this.kind});

  final EnglishLessonKind kind;

  @override
  Widget build(BuildContext context) =>
      _TinyChip(label: kind.label.toUpperCase());
}

class _TinyChip extends StatelessWidget {
  const _TinyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: _elevated,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: _tertiary,
            fontFamily: 'Cascadia Mono',
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _AiExtensionNote extends StatelessWidget {
  const _AiExtensionNote();

  @override
  Widget build(BuildContext context) => _HoverPanel(
        color: _elevated,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_outlined, color: _amber, size: 19),
            SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI ADVISOR / FUTURE EXTENSION POINT',
                    style: TextStyle(
                      color: _amber,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Базовый путь уже работает без AI. В будущем advisor сможет анализировать ошибки и темп, перестраивать следующие уроки и продолжать программу после B2, возвращая новые версии того же EnglishPlan.',
                    style: TextStyle(
                      color: _secondary,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SportsRoadmapScreen extends StatefulWidget {
  const _SportsRoadmapScreen({
    required this.database,
    required this.onCapture,
    required this.onChanged,
  });

  final LocalDatabase database;
  final VoidCallback onCapture;
  final VoidCallback onChanged;

  @override
  State<_SportsRoadmapScreen> createState() => _SportsRoadmapScreenState();
}

class _SportsRoadmapScreenState extends State<_SportsRoadmapScreen> {
  SportWorkoutPlan? _selectedWorkout;
  SportTrainingProfile? _profile;
  bool _editingProfile = false;

  Future<void> _finishAdaptation() async {
    final profile = _profile;
    if (profile == null) return;
    final updated = profile.copyWith(adaptation: 'none');
    await widget.database
        .saveSportTrainingProfileJson(jsonEncode(updated.toJson()));
    if (mounted) setState(() => _profile = updated);
  }

  @override
  void initState() {
    super.initState();
    final raw = widget.database.sportTrainingProfileJson();
    if (raw == null) return;
    try {
      _profile = SportTrainingProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // A corrupt optional Sport profile should never hide existing workouts.
      _profile = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null || _editingProfile) {
      return _SportIntakeChat(
        database: widget.database,
        initial: _editingProfile ? _profile : null,
        onCancel: _editingProfile
            ? () => setState(() => _editingProfile = false)
            : null,
        onSaved: (profile) => setState(() {
          _profile = profile;
          _editingProfile = false;
        }),
      );
    }
    final profile = _profile!;
    final adaptation = profile.adaptation;
    final pausedForInjury = adaptation == 'injury-pause';
    final preset = presetById(profile.presetId);
    final roadmap = buildSportRoadmap(presetId: preset.id);
    final completed = widget.database.completedSportWorkouts();
    if (_selectedWorkout != null) {
      return _SportsWorkoutDetail(
        workout: _selectedWorkout!,
        database: widget.database,
        onBack: () => setState(() => _selectedWorkout = null),
        onCompleted: () {
          setState(() => _selectedWorkout = null);
          widget.onChanged();
        },
      );
    }
    final active = roadmap.workouts.firstWhere(
      (workout) => !completed.contains(workout.id),
      orElse: () => roadmap.workouts.last,
    );
    return _PageScroll(
      child: ConstrainedBox(
        constraints: const BoxConstraints(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              eyebrow: 'SPORTS / LOAD PATH',
              title: 'Сначала база. Потом умнее.',
              description:
                  '${preset.title}: ${preset.summary} Первые 3 тренировки — самостоятельная фиксация фактических весов и подходов.',
              trailing: _ModuleIcon(icon: Icons.fitness_center_outlined),
            ),
            const SizedBox(height: 24),
            _SportProfilePanel(
              profile: profile,
              preset: preset,
              onEdit: () => setState(() => _editingProfile = true),
            ),
            const SizedBox(height: 20),
            if (adaptation != 'none') ...[
              _SportAdaptationPanel(
                adaptation: adaptation,
                onFinish: _finishAdaptation,
              ),
              const SizedBox(height: 20),
            ],
            _SportsPathSummary(
              roadmap: roadmap,
              completed: completed,
              active: active,
              onCapture: widget.onCapture,
            ),
            const SizedBox(height: 20),
            _SportsRulesPanel(),
            const SizedBox(height: 12),
            _HoverPanel(
              color: _surface,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final workout in roadmap.workouts.take(18))
                    _SportsSessionRow(
                      workout: workout,
                      completed: completed.contains(workout.id),
                      onOpen: pausedForInjury
                          ? null
                          : () => setState(() => _selectedWorkout = workout),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SportsAdvisorNote(),
          ],
        ),
      ),
    );
  }
}

class _SportProfilePanel extends StatelessWidget {
  const _SportProfilePanel({
    required this.profile,
    required this.preset,
    required this.onEdit,
  });

  final SportTrainingProfile profile;
  final SportPreset preset;
  final VoidCallback onEdit;

  Future<void> _openSource(BuildContext context) async {
    final uri = Uri.tryParse(profile.sourceUrl);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть источник программы.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _HoverPanel(
        color: _elevated,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _PanelKicker(
                    icon: Icons.psychology_alt_outlined,
                    label: 'SPORT PROFILE / LOCAL MATCH',
                  ),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('ИЗМЕНИТЬ'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(preset.title,
                style: TextStyle(
                    color: _primary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(preset.structure,
                style:
                    TextStyle(color: _secondary, fontSize: 12, height: 1.45)),
            const SizedBox(height: 11),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _TinyChip(
                    label:
                        '${profile.ageGroup.label} · ${profile.experience.label}'),
                _TinyChip(label: profile.goal.label.toUpperCase()),
                _TinyChip(label: '${profile.daysPerWeek} ДН./НЕД.'),
                if (profile.focusAreas.isNotEmpty)
                  _TinyChip(
                      label: profile.focusAreas.join(' · ').toUpperCase()),
                if (profile.hasLimitations)
                  const _TinyChip(label: 'ОГРАНИЧЕНИЯ УЧТЕНЫ'),
              ],
            ),
            if (profile.hasExternalSource) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _openSource(context),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(profile.sourceTitle.trim().isEmpty
                    ? 'ОТКРЫТЬ УКАЗАННЫЙ ИСТОЧНИК'
                    : 'ИСТОЧНИК: ${profile.sourceTitle.trim().toUpperCase()}'),
              ),
            ],
          ],
        ),
      );
}

enum _SportChatStep {
  age,
  experience,
  frequency,
  limitations,
  safety,
  goal,
  focus,
  source,
  sourceLink,
  proposal,
}

class _SportChatMessage {
  const _SportChatMessage(this.text, {required this.isUser});

  final String text;
  final bool isUser;
}

class _SportIntakeChat extends StatefulWidget {
  const _SportIntakeChat({
    required this.database,
    required this.initial,
    required this.onSaved,
    this.onCancel,
  });

  final LocalDatabase database;
  final SportTrainingProfile? initial;
  final ValueChanged<SportTrainingProfile> onSaved;
  final VoidCallback? onCancel;

  @override
  State<_SportIntakeChat> createState() => _SportIntakeChatState();
}

class _SportIntakeChatState extends State<_SportIntakeChat> {
  late SportAgeGroup _ageGroup;
  late SportExperience _experience;
  late SportGoal _goal;
  late int _daysPerWeek;
  late String _presetId;
  late final TextEditingController _limitations;
  late final TextEditingController _sourceUrl;
  late final TextEditingController _textAnswer;
  final _composerFocus = FocusNode(debugLabel: 'sport-intake-composer');
  final Set<String> _focusAreas = {};
  final List<_SportChatMessage> _messages = [];
  _SportChatStep _step = _SportChatStep.age;
  bool _medicalAware = false;
  bool _awaitingLimitationDetails = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _ageGroup = initial?.ageGroup ?? SportAgeGroup.age18to34;
    _experience = initial?.experience ?? SportExperience.newToTraining;
    _goal = initial?.goal ?? SportGoal.generalHealth;
    _daysPerWeek = initial?.daysPerWeek ?? 3;
    _presetId = initial?.presetId ?? 'balanced-start';
    _focusAreas.addAll(initial?.focusAreas ?? const []);
    _limitations = TextEditingController(text: initial?.limitations ?? '');
    _sourceUrl = TextEditingController(text: initial?.sourceUrl ?? '');
    _textAnswer = TextEditingController();
    _medicalAware = initial?.hasMedicalClearance ?? false;
    _messages.add(const _SportChatMessage(
      'Настройка займёт несколько коротких вопросов. Вы можете нажимать готовые варианты, а перед сохранением увидите весь план.',
      isUser: false,
    ));
    _ask(
        'К какой возрастной группе вы относитесь? Это нужно, чтобы безопаснее подобрать объём и темп нагрузки.');
  }

  @override
  void dispose() {
    _limitations.dispose();
    _sourceUrl.dispose();
    _textAnswer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _refreshRecommendation() {
    _presetId = recommendSportPreset(
      goal: _goal,
      experience: _experience,
      hasLimitations: _limitations.text.trim().isNotEmpty,
      focusAreas: _focusAreas.toList(),
    ).id;
  }

  void _ask(String message) =>
      _messages.add(_SportChatMessage(message, isUser: false));

  void _reply(String message) =>
      _messages.add(_SportChatMessage(message, isUser: true));

  void _selectAge(SportAgeGroup value, {String? replyText}) => setState(() {
        _ageGroup = value;
        _reply(replyText ?? value.label);
        _step = _SportChatStep.experience;
        _ask('Спасибо. Какой у вас сейчас опыт силовых тренировок?');
      });

  void _selectExperience(SportExperience value, {String? replyText}) =>
      setState(() {
        _experience = value;
        _reply(replyText ?? value.label);
        _refreshRecommendation();
        _step = _SportChatStep.frequency;
        _ask(
            'Сколько силовых тренировок в неделю реально помещается в твоём графике?');
      });

  void _selectFrequency(int value, {String? replyText}) => setState(() {
        _daysPerWeek = value;
        _reply(replyText ?? '$value ${value == 2 ? 'дня' : 'дня'} в неделю');
        _step = _SportChatStep.limitations;
        _ask(
            'Есть травмы, инвалидность, недавние операции, боль или ограничения врача, которые нужно учесть?');
      });

  void _noLimitations() => setState(() {
        _limitations.text = '';
        _reply('Нет, ограничений нет.');
        _step = _SportChatStep.safety;
        _ask(
            'Хорошо. При боли или врачебных ограничениях я не заменяю специалиста и не подбираю лечение. Понятно?');
      });

  void _describeLimitations() => setState(() {
        _reply('Да, хочу описать ограничения.');
        _awaitingLimitationDetails = true;
        _ask(
            'Опиши их так, как тебе удобно. Например: «болит колено при глубоком приседе» или «есть ограничение врача».');
      });

  void _confirmSafety({String? replyText}) => setState(() {
        _medicalAware = true;
        _reply(replyText ?? 'Понимаю.');
        _step = _SportChatStep.goal;
        _ask('Какая главная цель тренировок сейчас?');
      });

  void _selectGoal(SportGoal value, {String? replyText}) => setState(() {
        _goal = value;
        _reply(replyText ?? value.label);
        _refreshRecommendation();
        _step = _SportChatStep.focus;
        _ask(
            'Нужно сделать акцент на конкретной части тела? Можно выбрать вариант или написать своими словами.');
      });

  void _selectFocus(String value) => setState(() {
        _focusAreas
          ..clear()
          ..add(value);
        _reply(value);
        _refreshRecommendation();
        _step = _SportChatStep.source;
        _ask(
            'У тебя есть открытая статья или готовый план, на который нужно ориентироваться?');
      });

  void _noFocus() => setState(() {
        _focusAreas.clear();
        _reply('Нет, без отдельного акцента.');
        _refreshRecommendation();
        _step = _SportChatStep.source;
        _ask(
            'У тебя есть открытая статья или готовый план, на который нужно ориентироваться?');
      });

  void _useLocalRecommendation() => setState(() {
        _reply('Нет, подбери вариант плана автоматически.');
        _sourceUrl.text = '';
        _showProposal();
      });

  void _askForSourceLink() => setState(() {
        _reply('Да, у меня есть ссылка.');
        _step = _SportChatStep.sourceLink;
        _ask(
            'Вставьте полную ссылку на статью или программу. Она сохранится как источник, а приложение предложит ближайший безопасный вариант плана.');
      });

  void _showProposal() {
    _refreshRecommendation();
    final recommendation = presetById(_presetId);
    _step = _SportChatStep.proposal;
    _ask(
        'По твоим ответам предлагаю «${recommendation.title}». ${recommendation.summary}');
    _ask('Режим: ${recommendation.frequency}. ${recommendation.safetyNote}');
  }

  SportAgeGroup? _ageFromText(String value) {
    final number = RegExp(r'\d{1,2}').firstMatch(value)?.group(0);
    final age = number == null ? null : int.tryParse(number);
    if (age != null) {
      if (age < 18) return SportAgeGroup.under18;
      if (age <= 34) return SportAgeGroup.age18to34;
      if (age <= 49) return SportAgeGroup.age35to49;
      if (age <= 64) return SportAgeGroup.age50to64;
      return SportAgeGroup.age65plus;
    }
    if (value.contains('до 18') || value.contains('подрост')) {
      return SportAgeGroup.under18;
    }
    if (value.contains('65')) return SportAgeGroup.age65plus;
    if (value.contains('50')) return SportAgeGroup.age50to64;
    if (value.contains('35')) return SportAgeGroup.age35to49;
    return null;
  }

  SportExperience? _experienceFromText(String value) {
    if (value.contains('возвращ') || value.contains('перерыв')) {
      return SportExperience.returning;
    }
    if (value.contains('регуляр') ||
        value.contains('давно') ||
        value.contains('год')) {
      return SportExperience.regular;
    }
    if (value.contains('начина') ||
        value.contains('нович') ||
        value.contains('не трениров')) {
      return SportExperience.newToTraining;
    }
    return null;
  }

  SportGoal? _goalFromText(String value) {
    if (value.contains('похуд') ||
        value.contains('сброс') ||
        value.contains('вес')) {
      return SportGoal.fatLoss;
    }
    if (value.contains('мышц') ||
        value.contains('массу') ||
        value.contains('масса')) {
      return SportGoal.muscleGain;
    }
    if (value.contains('сил')) return SportGoal.strength;
    if (value.contains('вынослив') || value.contains('бег'))
      return SportGoal.endurance;
    if (value.contains('здоров') || value.contains('тонус')) {
      return SportGoal.generalHealth;
    }
    if (value.contains('плеч') ||
        value.contains('спин') ||
        value.contains('ног') ||
        value.contains('рук') ||
        value.contains('груд')) {
      return SportGoal.targeted;
    }
    return null;
  }

  void _submitText() {
    final answer = _sanitizeSportChatMessage(_textAnswer.text);
    if (answer.isEmpty) return;
    final normalized = answer.toLowerCase();
    if (_step == _SportChatStep.age) {
      final value = _ageFromText(normalized);
      if (value != null) {
        _textAnswer.clear();
        _selectAge(value, replyText: answer);
        return;
      }
    }
    if (_step == _SportChatStep.experience) {
      final value = _experienceFromText(normalized);
      if (value != null) {
        _textAnswer.clear();
        _selectExperience(value, replyText: answer);
        return;
      }
    }
    if (_step == _SportChatStep.frequency) {
      final days = RegExp(r'\b[2-5]\b').firstMatch(normalized)?.group(0);
      if (days != null) {
        _textAnswer.clear();
        _selectFrequency(int.parse(days), replyText: answer);
        return;
      }
    }
    if (_step == _SportChatStep.limitations && !_awaitingLimitationDetails) {
      _textAnswer.clear();
      setState(() {
        _reply(answer);
        final saysNo =
            normalized.contains('нет') || normalized.contains('не было');
        _limitations.text = saysNo ? '' : answer;
        _refreshRecommendation();
        _step = _SportChatStep.safety;
        _ask(saysNo
            ? 'Хорошо. При боли или врачебных ограничениях я не заменяю специалиста и не подбираю лечение. Понятно?'
            : 'Я учту это как ограничение и предложу осторожный старт. При боли или врачебных ограничениях я не заменяю специалиста. Понятно?');
      });
      return;
    }
    if (_step == _SportChatStep.safety &&
        (normalized.contains('понят') ||
            normalized.contains('соглас') ||
            normalized == 'да')) {
      _textAnswer.clear();
      _confirmSafety(replyText: answer);
      return;
    }
    if (_step == _SportChatStep.goal) {
      final value = _goalFromText(normalized);
      if (value != null) {
        _textAnswer.clear();
        _selectGoal(value, replyText: answer);
        return;
      }
    }
    if (_step == _SportChatStep.source) {
      final uri = Uri.tryParse(answer);
      if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
        _textAnswer.clear();
        setState(() {
          _reply(answer);
          _sourceUrl.text = answer;
          _showProposal();
        });
        return;
      }
      if (normalized.contains('нет') || normalized.contains('подбери')) {
        _textAnswer.clear();
        _useLocalRecommendation();
        return;
      }
    }
    setState(() {
      _textAnswer.clear();
      _reply(answer);
      if (_awaitingLimitationDetails) {
        _limitations.text = answer;
        _awaitingLimitationDetails = false;
        _refreshRecommendation();
        _step = _SportChatStep.safety;
        _ask(
            'Я учту это как ограничение и предложу осторожный старт. При боли или врачебных ограничениях я не заменяю специалиста. Понятно?');
        return;
      }
      if (_step == _SportChatStep.focus) {
        _focusAreas
          ..clear()
          ..add(answer);
        _refreshRecommendation();
        _step = _SportChatStep.source;
        _ask(
            'Понял, добавил акцент: $answer. У тебя есть открытая статья или готовый план, на который нужно ориентироваться?');
        return;
      }
      if (_step == _SportChatStep.sourceLink) {
        final uri = Uri.tryParse(answer);
        if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
          _error = 'Нужна полная ссылка, начинающаяся с http:// или https://.';
          return;
        }
        _sourceUrl.text = answer;
        _showProposal();
        return;
      }
      _ask(
          'Можно продолжить своим сообщением или выбрать подходящий вариант ниже.');
    });
  }

  void _appendToComposer(String text) {
    final selection = _textAnswer.selection;
    final start = selection.isValid ? selection.start : _textAnswer.text.length;
    final end = selection.isValid ? selection.end : _textAnswer.text.length;
    _textAnswer.value = _textAnswer.value.copyWith(
      text: _textAnswer.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    );
  }

  KeyEventResult _handleChatKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (!_composerFocus.hasFocus) {
          _appendToComposer('\n');
          _composerFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      _submitText();
      return KeyEventResult.handled;
    }
    if (_composerFocus.hasFocus ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character == null ||
        character.isEmpty ||
        character.codeUnitAt(0) < 32) {
      return KeyEventResult.ignored;
    }
    _appendToComposer(character);
    _composerFocus.requestFocus();
    return KeyEventResult.handled;
  }

  Future<void> _save() async {
    if (!_medicalAware) {
      setState(() =>
          _error = 'Сначала нужно подтвердить правило безопасности в диалоге.');
      return;
    }
    final profile = SportTrainingProfile(
      ageGroup: _ageGroup,
      experience: _experience,
      goal: _goal,
      daysPerWeek: _daysPerWeek,
      focusAreas: _focusAreas.toList()..sort(),
      limitations: _limitations.text.trim(),
      hasMedicalClearance: _medicalAware,
      presetId: _presetId,
      sourceUrl: _sourceUrl.text.trim(),
      sourceTitle: _sourceUrl.text.trim().isEmpty ? '' : 'Открытая программа',
    );
    await widget.database
        .saveSportTrainingProfileJson(jsonEncode(profile.toJson()));
    if (mounted) widget.onSaved(profile);
  }

  Widget _bubble(_SportChatMessage message) => Align(
        alignment:
            message.isUser ? const Alignment(0.58, 0) : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: message.isUser ? _amber.withAlpha(28) : _elevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: message.isUser ? _amberLine : _line),
          ),
          child: Text(message.text,
              style: TextStyle(
                  color: message.isUser ? _primary : _secondary,
                  fontSize: 13,
                  height: 1.45)),
        ),
      );

  List<Widget> _quickReplies() {
    List<Widget> buttons(List<({String label, VoidCallback action})> items) => [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                OutlinedButton(onPressed: item.action, child: Text(item.label)),
            ],
          ),
        ];
    return switch (_step) {
      _SportChatStep.age => buttons([
          for (final item in SportAgeGroup.values)
            (label: item.label, action: () => _selectAge(item))
        ]),
      _SportChatStep.experience => buttons([
          for (final item in SportExperience.values)
            (label: item.label, action: () => _selectExperience(item))
        ]),
      _SportChatStep.frequency => buttons([
          for (final value in [2, 3, 4, 5])
            (
              label: '$value дня в неделю',
              action: () => _selectFrequency(value)
            )
        ]),
      _SportChatStep.limitations when !_awaitingLimitationDetails => buttons([
          (label: 'Нет ограничений', action: _noLimitations),
          (label: 'Да, опишу', action: _describeLimitations),
        ]),
      _SportChatStep.safety =>
        buttons([(label: 'Понимаю', action: _confirmSafety)]),
      _SportChatStep.goal => buttons([
          for (final item in SportGoal.values)
            (label: item.label, action: () => _selectGoal(item))
        ]),
      _SportChatStep.focus => buttons([
          for (final item in const [
            'грудь',
            'спина',
            'плечи',
            'руки',
            'ноги',
            'ягодицы',
            'корпус'
          ])
            (label: item, action: () => _selectFocus(item)),
          (label: 'Без акцента', action: _noFocus),
        ]),
      _SportChatStep.source => buttons([
          (label: 'Подобрать вариант плана', action: _useLocalRecommendation),
          (label: 'У меня есть ссылка', action: _askForSourceLink),
        ]),
      _SportChatStep.proposal => buttons([
          (label: 'Сохранить этот план', action: _save),
          for (final item in sportPresets.where((item) => item.id != _presetId))
            (
              label: item.title,
              action: () => setState(() {
                    _presetId = item.id;
                    _reply('Выбираю «${item.title}».');
                    _ask(
                        'Готово: выбран вариант «${item.title}». Нажмите «Сохранить этот план», если всё подходит.');
                  })
            ),
        ]),
      _ => const [],
    };
  }

  bool get _showsTextInput => false;

  String get _inputHint => _awaitingLimitationDetails
      ? 'Опиши ограничение…'
      : _step == _SportChatStep.sourceLink
          ? 'https://…'
          : 'Напишите сообщение…';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 700;
      return Focus(
        autofocus: true,
        onKeyEvent: _handleChatKey,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              narrow ? 12 : 28, 14, narrow ? 12 : 28, narrow ? 10 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _PageHeader(
                      eyebrow: 'ТРЕНИРОВКИ / ПЕРВАЯ НАСТРОЙКА',
                      title: 'Настроим безопасный старт.',
                      description:
                          'Выберите готовые ответы: цель, ограничения и доступное время. В конце вы увидите план до его сохранения.',
                    ),
                  ),
                  if (widget.onCancel != null)
                    TextButton.icon(
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.close, size: 17),
                      label: const Text('ОТМЕНА'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                  child: _HoverPanel(
                color: Colors.transparent,
                borderColor: _amberLine,
                highlightOnHover: false,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PanelKicker(
                        icon: Icons.tune_rounded,
                        label: 'ПАРАМЕТРЫ ВАШЕГО ПЛАНА'),
                    const SizedBox(height: 14),
                    Expanded(
                        child: ListView(
                      padding: const EdgeInsets.only(top: 4, bottom: 12),
                      children: [
                        for (final message in _messages) _bubble(message),
                        const SizedBox(height: 6),
                        ..._quickReplies(),
                        if (_showsTextInput) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: _textAnswer,
                                    onSubmitted: (_) => _submitText(),
                                    decoration:
                                        InputDecoration(hintText: _inputHint))),
                            const SizedBox(width: 8),
                            FilledButton(
                                onPressed: _submitText,
                                child: const Text('ОТПРАВИТЬ')),
                          ]),
                        ],
                        if (_step == _SportChatStep.proposal) ...[
                          const SizedBox(height: 12),
                          _HoverPanel(
                              color: _surface,
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(presetById(_presetId).title,
                                        style: TextStyle(
                                            color: _amber,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 5),
                                    Text(presetById(_presetId).structure,
                                        style: TextStyle(
                                            color: _secondary,
                                            fontSize: 12,
                                            height: 1.4)),
                                    if (_sourceUrl.text.trim().isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                          'Источник сохранён: ${_sourceUrl.text.trim()}',
                                          style: TextStyle(
                                              color: _tertiary, fontSize: 11))
                                    ],
                                  ])),
                        ],
                      ],
                    )),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      _NoticeBanner(message: _error!),
                    ],
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                          child: TextField(
                        controller: _textAnswer,
                        focusNode: _composerFocus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) => _submitText(),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 44, minHeight: 36),
                          prefixIcon:
                              const Icon(Icons.chat_bubble_outline_rounded),
                          hintText: _inputHint,
                        ),
                      )),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _submitText,
                        icon: const Icon(Icons.send, size: 16),
                        label: const Text('ОТПРАВИТЬ'),
                      ),
                    ]),
                  ],
                ),
              )),
            ],
          ),
        ),
      );
    });
  }
}

String _sanitizeSportChatMessage(String raw) {
  final cleaned = <String>[];
  var emptyLines = 0;
  for (final rawLine in raw.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) {
      emptyLines += 1;
      if (emptyLines > 3) break;
      cleaned.add('');
    } else {
      emptyLines = 0;
      cleaned.add(line);
    }
  }
  while (cleaned.isNotEmpty && cleaned.first.isEmpty) {
    cleaned.removeAt(0);
  }
  while (cleaned.isNotEmpty && cleaned.last.isEmpty) {
    cleaned.removeLast();
  }
  return cleaned.join('\n');
}

class _SportAdaptationPanel extends StatelessWidget {
  const _SportAdaptationPanel(
      {required this.adaptation, required this.onFinish});

  final String adaptation;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final injury = adaptation == 'injury-pause';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _base.withAlpha(220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: injury ? _red.withAlpha(180) : _amberLine),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
            injury
                ? Icons.health_and_safety_outlined
                : Icons.self_improvement_outlined,
            color: injury ? _red : _amber),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(injury ? 'СИЛОВЫЕ НА ПАУЗЕ' : 'БЛИЖАЙШАЯ ТРЕНИРОВКА ЗАМЕНЕНА',
              style: TextStyle(color: _primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            injury
                ? 'Это не медицинское назначение. При тревожных симптомах сначала обсудите состояние с квалифицированным специалистом. Когда возвращение безопасно, начните со щадящего варианта плана.'
                : 'Выполните лёгкую mobility/восстановление 25–35 минут. Силовая очередь A/B/C/D не продвигается.',
            style: TextStyle(color: _secondary, height: 1.4),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onFinish,
            child: Text(injury
                ? 'ВОЗОБНОВИТЬ ЛЁГКИЙ РЕЖИМ'
                : 'ВОССТАНОВЛЕНИЕ ВЫПОЛНЕНО'),
          ),
        ])),
      ]),
    );
  }
}

class _SportsPathSummary extends StatelessWidget {
  const _SportsPathSummary({
    required this.roadmap,
    required this.completed,
    required this.active,
    required this.onCapture,
  });

  final SportRoadmap roadmap;
  final Set<String> completed;
  final SportWorkoutPlan active;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final count = completed.length;
    final progress = count / roadmap.workouts.length;
    return _HoverPanel(
      borderColor: _amberLine,
      glowOnHover: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _PanelKicker(
                  icon: Icons.query_stats_outlined,
                  label: 'ПЛАН НА 90 ДНЕЙ · ПРОГРЕСС НА УСТРОЙСТВЕ',
                ),
              ),
              OutlinedButton.icon(
                onPressed: onCapture,
                icon: Icon(Icons.bolt, size: 16),
                label: Text('БЫСТРАЯ ЗАПИСЬ'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: _primary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5, left: 6),
                child: Text(
                  '/ ${roadmap.workouts.length} тренировок завершено',
                  style: TextStyle(color: _secondary, fontSize: 13),
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: _amber,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: _elevated,
              color: _amber,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _elevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                Icon(Icons.play_arrow_rounded, color: _amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEXT WORKOUT',
                        style: TextStyle(
                          color: _tertiary,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 9,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SESSION ${active.sessionNumber} · DAY ${active.dayNumber} · TEMPLATE ${active.template.label}',
                        style: TextStyle(
                          color: _amber,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active.template.title,
                        style: TextStyle(
                          color: _primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _TinyChip(
                  label: active.requiresManualBaseline
                      ? 'MANUAL BASELINE'
                      : 'LOAD ADVISOR',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SportsRulesPanel extends StatelessWidget {
  const _SportsRulesPanel();

  @override
  Widget build(BuildContext context) => _HoverPanel(
        color: _elevated,
        padding: EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _SportRule(
              icon: Icons.edit_note_outlined,
              title: '1–3 / MANUAL',
              text: 'Сам записываешь вес, повторы и подходы.',
            ),
            _SportRule(
              icon: Icons.auto_graph_outlined,
              title: '4+ / ESTIMATE',
              text: 'Ориентир строится по последнему подтверждённому весу.',
            ),
            _SportRule(
              icon: Icons.shield_outlined,
              title: 'NO INVENTED LOAD',
              text: 'Если истории нет, вес не придумывается.',
            ),
          ],
        ),
      );
}

class _SportRule extends StatelessWidget {
  const _SportRule(
      {required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 300,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _amber, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _amber,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(text, style: TextStyle(color: _secondary, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SportsSessionRow extends StatelessWidget {
  const _SportsSessionRow({
    required this.workout,
    required this.completed,
    required this.onOpen,
  });

  final SportWorkoutPlan workout;
  final bool completed;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onOpen,
        mouseCursor: onOpen == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: _line)),
          ),
          child: Row(
            children: [
              Icon(
                completed
                    ? Icons.check_circle_rounded
                    : Icons.play_circle_outline_rounded,
                color: completed ? _green : _amber,
                size: 21,
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Text(
                  'SESSION ${workout.sessionNumber.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: _tertiary,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 9,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DAY ${workout.dayNumber} · TEMPLATE ${workout.template.label} · ${workout.template.title}',
                      style: TextStyle(
                        color: completed ? _tertiary : _primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      children: [
                        _TinyChip(
                          label: workout.requiresManualBaseline
                              ? 'MANUAL WEIGHTS'
                              : 'LOAD ESTIMATE',
                        ),
                        _TinyChip(
                            label: '${workout.exercises.length} EXERCISES'),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '${workout.estimatedMinutes}m',
                style: TextStyle(
                  color: _secondary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 7),
              Icon(
                  onOpen == null
                      ? Icons.pause_circle_outline
                      : Icons.chevron_right,
                  color: _tertiary,
                  size: 17),
            ],
          ),
        ),
      );
}

class _SportsWorkoutDetail extends StatefulWidget {
  const _SportsWorkoutDetail({
    required this.workout,
    required this.database,
    required this.onBack,
    required this.onCompleted,
  });

  final SportWorkoutPlan workout;
  final LocalDatabase database;
  final VoidCallback onBack;
  final VoidCallback onCompleted;

  @override
  State<_SportsWorkoutDetail> createState() => _SportsWorkoutDetailState();
}

class _SportsWorkoutDetailState extends State<_SportsWorkoutDetail> {
  final _advisor = const DeterministicSportLoadAdvisor();
  final _weightControllers = <String, TextEditingController>{};
  final _repControllers = <String, TextEditingController>{};
  final _completedSets = <String, bool>{};
  Map<String, SportLoadAdvice> _advice = {};
  Set<String> _savedExercises = {};
  bool _loadingAdvice = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final logs = widget.database.sportSetLogsFor(widget.workout.id);
    for (final exercise in widget.workout.exercises) {
      for (var set = 1; set <= exercise.targetSets; set++) {
        final key = _key(exercise.id, set);
        SportSetLog? log;
        for (final candidate in logs) {
          if (candidate.setNumber == set &&
              candidate.exerciseId == exercise.id) {
            log = candidate;
            break;
          }
        }
        _weightControllers[key] = TextEditingController(
          text: log == null || log.weightKg == 0 ? '' : _number(log.weightKg),
        );
        _repControllers[key] = TextEditingController(
          text: log == null || log.repetitions == 0 ? '' : '${log.repetitions}',
        );
        _completedSets[key] = log?.completed ?? false;
      }
    }
    _loadAdvice();
  }

  String _key(String exerciseId, int setNumber) => '$exerciseId-$setNumber';

  String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  Future<void> _loadAdvice() async {
    final history = [
      for (final log in widget.database.allSportSetLogs())
        SportHistorySet(
          sessionNumber: log.sessionNumber,
          exerciseId: log.exerciseId,
          weightKg: log.weightKg,
          repetitions: log.repetitions,
          completed: log.completed,
        ),
    ];
    final advice = await _advisor.suggestLoads(
      widget.workout,
      history: history,
      recoveryNote: null,
    );
    if (mounted) {
      setState(() {
        _advice = advice;
        _loadingAdvice = false;
      });
    }
  }

  Future<void> _saveExercise(SportExercisePlan exercise) async {
    for (var set = 1; set <= exercise.targetSets; set++) {
      final key = _key(exercise.id, set);
      final weight =
          double.tryParse(_weightControllers[key]!.text.replaceAll(',', '.')) ??
              0;
      final repetitions = int.tryParse(_repControllers[key]!.text) ?? 0;
      await widget.database.saveSportSetLog(
        sessionId: widget.workout.id,
        sessionNumber: widget.workout.sessionNumber,
        exerciseId: exercise.id,
        setNumber: set,
        weightKg: weight,
        repetitions: repetitions,
        completed: _completedSets[key] ?? false,
      );
    }
    if (mounted) {
      setState(() => _savedExercises = {..._savedExercises, exercise.id});
    }
  }

  bool _allSetsComplete() {
    for (final exercise in widget.workout.exercises) {
      for (var set = 1; set <= exercise.targetSets; set++) {
        final key = _key(exercise.id, set);
        final weight = double.tryParse(
                _weightControllers[key]!.text.replaceAll(',', '.')) ??
            0;
        final reps = int.tryParse(_repControllers[key]!.text) ?? 0;
        if (weight <= 0 || reps <= 0 || !(_completedSets[key] ?? false)) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _finish() async {
    if (!_allSetsComplete()) {
      setState(() => _error =
          'Сохрани фактический вес, повторы и отметку каждого подхода.');
      return;
    }
    for (final exercise in widget.workout.exercises) {
      await _saveExercise(exercise);
    }
    await widget.database.setSportWorkoutCompleted(
      widget.workout.id,
      widget.workout.sessionNumber,
      true,
    );
    widget.onCompleted();
  }

  @override
  void dispose() {
    for (final controller in _weightControllers.values) {
      controller.dispose();
    }
    for (final controller in _repControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PageScroll(
        child: ConstrainedBox(
          constraints: const BoxConstraints(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: widget.onBack,
                icon: Icon(Icons.arrow_back, size: 17),
                label: Text('К ПЛАНУ ТРЕНИРОВОК'),
                style: TextButton.styleFrom(foregroundColor: _secondary),
              ),
              const SizedBox(height: 8),
              _PageHeader(
                eyebrow:
                    'SPORTS / SESSION ${widget.workout.sessionNumber.toString().padLeft(2, '0')} / DAY ${widget.workout.dayNumber}',
                title:
                    'Template ${widget.workout.template.label} · ${widget.workout.template.title}',
                description:
                    'Фиксируй реальные подходы. Рекомендация веса — ориентир, а техника и самочувствие важнее цифры.',
                trailing: _ModuleIcon(icon: Icons.fitness_center_outlined),
              ),
              const SizedBox(height: 18),
              _HoverPanel(
                borderColor: _amberLine,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                      child: _PanelKicker(
                        icon: Icons.auto_graph_outlined,
                        label: 'LOAD MODE',
                      ),
                    ),
                    _TinyChip(
                      label: widget.workout.requiresManualBaseline
                          ? 'MANUAL BASELINE / 1–3'
                          : 'ADVISOR ESTIMATE / 4+',
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _finish,
                      icon: Icon(Icons.check, size: 17),
                      label: Text('FINISH WORKOUT'),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _NoticeBanner(message: _error!),
              ],
              const SizedBox(height: 14),
              if (_loadingAdvice)
                _LoadingState(label: 'Считаем безопасные ориентиры')
              else
                for (final exercise in widget.workout.exercises) ...[
                  _SportsExerciseCard(
                    exercise: exercise,
                    advice: _advice[exercise.id],
                    weightControllers: _weightControllers,
                    repControllers: _repControllers,
                    completedSets: _completedSets,
                    saved: _savedExercises.contains(exercise.id),
                    keyFor: _key,
                    onSetCompleted: (set, value) => setState(
                      () => _completedSets[_key(exercise.id, set)] = value,
                    ),
                    onSave: () => _saveExercise(exercise),
                  ),
                  const SizedBox(height: 10),
                ],
              _SportsAdvisorNote(),
            ],
          ),
        ),
      );
}

class _SportsExerciseCard extends StatelessWidget {
  const _SportsExerciseCard({
    required this.exercise,
    required this.advice,
    required this.weightControllers,
    required this.repControllers,
    required this.completedSets,
    required this.keyFor,
    required this.onSetCompleted,
    required this.onSave,
    required this.saved,
  });

  final SportExercisePlan exercise;
  final SportLoadAdvice? advice;
  final Map<String, TextEditingController> weightControllers;
  final Map<String, TextEditingController> repControllers;
  final Map<String, bool> completedSets;
  final String Function(String, int) keyFor;
  final void Function(int, bool) onSetCompleted;
  final VoidCallback onSave;
  final bool saved;

  @override
  Widget build(BuildContext context) => _HoverPanel(
        color: _surface,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exercise.name,
                    style: TextStyle(
                      color: _primary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _TinyChip(
                    label:
                        '${exercise.targetSets} SETS · ${exercise.repRange}'),
                if (saved) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, color: _green, size: 18),
                ],
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${exercise.equipment} · ${exercise.technique}',
              style: TextStyle(color: _secondary, fontSize: 11, height: 1.35),
            ),
            const SizedBox(height: 11),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _elevated,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: _line),
              ),
              child: Text(
                advice?.weightKg == null
                    ? advice?.reason ?? 'Введи фактический вес вручную.'
                    : 'Ориентир ${advice!.weightKg} kg · ${advice!.reason}',
                style: TextStyle(
                  color: advice?.weightKg == null ? _secondary : _amber,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (var set = 1; set <= exercise.targetSets; set++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        'SET $set',
                        style: TextStyle(
                          color: _tertiary,
                          fontFamily: 'Cascadia Mono',
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: weightControllers[keyFor(exercise.id, set)],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'kg',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: repControllers[keyFor(exercise.id, set)],
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'reps',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                      ),
                    ),
                    Checkbox(
                      value: completedSets[keyFor(exercise.id, set)] ?? false,
                      onChanged: (value) => onSetCompleted(set, value ?? false),
                      activeColor: _amber,
                      checkColor: _base,
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: onSave,
              icon: Icon(Icons.save_outlined, size: 16),
              label: Text('SAVE SETS'),
            ),
          ],
        ),
      );
}

class _SportsAdvisorNote extends StatelessWidget {
  const _SportsAdvisorNote();

  @override
  Widget build(BuildContext context) => _HoverPanel(
        color: _elevated,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_outlined, color: _amber, size: 19),
            SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LOAD ADVISOR / AI READY, LOCAL BASELINE NOW',
                    style: TextStyle(
                      color: _amber,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Первые три тренировки дают личную базу. С четвёртой детерминированный advisor предлагает небольшой шаг от последнего подтверждённого веса; будущий AI сможет учитывать RIR, сон, восстановление и технику.',
                    style: TextStyle(
                        color: _secondary, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ModuleScreen extends StatelessWidget {
  const _ModuleScreen({
    required this.name,
    required this.icon,
    required this.description,
    required this.database,
    required this.type,
    required this.onCapture,
  });

  final String name;
  final IconData icon;
  final String description;
  final LocalDatabase database;
  final CaptureType type;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    if (type == CaptureType.expense) {
      return _MoneyWorkspace(database: database, onCapture: onCapture);
    }
    final records = database
        .all()
        .where((record) => record.draft.type == type)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final todayRecords =
        records.where((record) => record.draft.date == today).length;
    final pendingRecords = records.where((record) => record.syncedAt == null);
    final actionTitle =
        type == CaptureType.salesCall ? 'Добавить звонок' : 'Добавить операцию';
    final actionDescription = type == CaptureType.salesCall
        ? 'Зафиксируйте компанию, результат разговора и следующий шаг.'
        : 'Запишите расход или доход, чтобы не держать детали в голове.';
    final example = type == CaptureType.salesCall
        ? 'Позвонил в Acme, ждём ответ до пятницы'
        : 'Кофе и обед — 85 000 сум, карта';
    return _PageScroll(
      child: ConstrainedBox(
        constraints: const BoxConstraints(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              eyebrow: 'РАЗДЕЛ / ${name.toUpperCase()}',
              title: name,
              description: description,
              trailing: _ModuleIcon(icon: icon),
            ),
            const SizedBox(height: 22),
            _ModuleMetrics(
              records: records.length,
              today: todayRecords,
              pending: pendingRecords.length,
              lastDate: records.isEmpty ? '—' : records.first.draft.date,
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final action = _HoverPanel(
                  borderColor: _amberLine,
                  glowOnHover: true,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PanelKicker(
                        icon: Icons.add_circle_outline,
                        label: 'БЫСТРОЕ ДЕЙСТВИЕ',
                      ),
                      const SizedBox(height: 13),
                      Text(
                        actionTitle,
                        style: TextStyle(
                          color: _primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        actionDescription,
                        style: TextStyle(
                          color: _secondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: onCapture,
                        icon: Icon(Icons.add, size: 17),
                        label: Text(actionTitle),
                      ),
                    ],
                  ),
                );
                final examplePanel = _HoverPanel(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PanelKicker(
                        icon: Icons.lightbulb_outline,
                        label: 'ПРИМЕР ЗАПИСИ',
                      ),
                      const SizedBox(height: 13),
                      Text(
                        '«$example»',
                        style: TextStyle(
                          color: _primary,
                          fontSize: 16,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'После разбора вы сможете проверить детали и подтвердить запись.',
                        style: TextStyle(
                          color: _secondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                );
                return wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: action),
                          const SizedBox(width: 14),
                          Expanded(flex: 5, child: examplePanel),
                        ],
                      )
                    : Column(
                        children: [
                          action,
                          const SizedBox(height: 14),
                          examplePanel
                        ],
                      );
              },
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              eyebrow: 'ИСТОРИЯ ЗАПИСЕЙ',
              title: 'Последние записи',
              trailing: Text(
                records.isEmpty ? 'ПОКА ПУСТО' : 'ПОСЛЕДНИЕ 20',
                style: TextStyle(
                  color: _tertiary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              SizedBox(
                width: double.infinity,
                child: _EmptyState(name: name, onCapture: onCapture),
              )
            else
              ...records.take(20).map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RecordTile(
                        title: _title(record.draft),
                        subtitle:
                            '${record.draft.date} · ${record.syncedAt == null ? 'ожидает sync' : 'синхронизировано'}',
                        detail: _detail(record.draft),
                        synced: record.syncedAt != null,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  String _title(CaptureDraft draft) => switch (draft.type) {
        CaptureType.expense ||
        CaptureType.income =>
          draft.description ?? draft.type.wireName,
        CaptureType.salesCall => draft.company ?? 'Звонок',
        CaptureType.english => draft.completedTask ?? 'English',
        CaptureType.sports => draft.activityType ?? 'Тренировка',
      };

  String _detail(CaptureDraft draft) => switch (draft.type) {
        CaptureType.expense || CaptureType.income => draft.amount == null
            ? ''
            : '${draft.amount!.round()} ${draft.currency}',
        CaptureType.salesCall => draft.result ?? '',
        CaptureType.english ||
        CaptureType.sports =>
          draft.durationMinutes == null ? '' : '${draft.durationMinutes} мин',
      };
}

class _MoneyWorkspace extends StatefulWidget {
  const _MoneyWorkspace({required this.database, required this.onCapture});

  final LocalDatabase database;
  final VoidCallback onCapture;

  @override
  State<_MoneyWorkspace> createState() => _MoneyWorkspaceState();
}

class _MoneyWorkspaceState extends State<_MoneyWorkspace> {
  int _tab = 0;
  int _filter = 0;
  String _query = '';
  List<MoneyAccount> _accounts = const [];
  List<MoneyCategory> _categories = const [];
  List<MoneyTransaction> _transactions = const [];
  List<MoneyObligation> _obligations = const [];
  List<MoneyRecurringTemplate> _recurring = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final dedicated = widget.database.moneyTransactions();
    final dedicatedIds = dedicated.map((item) => item.id).toSet();
    final canonicalCaptureIds =
        widget.database.canonicalMoneyCaptureIdsForSyntheticExclusion();
    final accounts = widget.database.moneyAccounts();
    final categories = widget.database.moneyCategories();
    final legacy = widget.database
        .all()
        .where((record) =>
            record.draft.type == CaptureType.expense ||
            record.draft.type == CaptureType.income)
        .where((record) =>
            record.draft.amount != null &&
            !dedicatedIds.contains(record.id) &&
            !canonicalCaptureIds.contains(record.id))
        .map((record) => _legacyTransaction(record, categories, accounts))
        .toList();
    setState(() {
      _accounts = accounts;
      _categories = categories;
      _transactions = [...dedicated, ...legacy]
        ..sort((a, b) => b.date.compareTo(a.date));
      _obligations = widget.database.moneyObligations();
      _recurring = widget.database.moneyRecurring();
    });
  }

  MoneyTransaction _legacyTransaction(CaptureRecord record,
      List<MoneyCategory> categories, List<MoneyAccount> accounts) {
    final draft = record.draft;
    final income = draft.type == CaptureType.income;
    final payment = draft.paymentMethod == 'cash'
        ? MoneyPaymentMethod.cash
        : draft.paymentMethod == 'bank'
            ? MoneyPaymentMethod.bank
            : MoneyPaymentMethod.card;
    final account =
        payment == MoneyPaymentMethod.cash ? 'cash-main' : 'card-main';
    final kind = income ? MoneyCategoryKind.income : MoneyCategoryKind.expense;
    final category = categories
        .where((item) =>
            item.kind == kind &&
            (item.id == draft.category ||
                item.name.toLowerCase() == draft.category?.toLowerCase()))
        .toList();
    return MoneyTransaction(
      id: record.id,
      date: draft.date,
      type: income ? MoneyTransactionType.income : MoneyTransactionType.expense,
      amount: draft.amount!,
      currency: draft.currency,
      counterparty: '',
      categoryId: category.isNotEmpty
          ? category.first.id
          : (income ? 'other-income' : 'other-expense'),
      purpose: draft.description ?? draft.originalText,
      paymentMethod: payment,
      accountId: accounts.any((item) => item.id == account)
          ? account
          : (accounts.isEmpty ? account : accounts.first.id),
      recurring: false,
      status: MoneyTransactionStatus.completed,
      essential: true,
      comment: draft.comment ?? 'Перенесено из быстрой записи',
      createdAt: record.createdAt,
    );
  }

  String _money(num value, [String currency = 'UZS']) {
    final digits = currency == 'USD' ? 2 : 0;
    final formatted = value.toStringAsFixed(digits).replaceAllMapped(
          RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
          (_) => ' ',
        );
    return '$formatted ${currency == 'USD' ? '\$' : 'сум'}';
  }

  String _categoryName(String id) {
    if (id == LocalDatabase.unclassifiedCategoryId)
      return 'Не классифицировано';
    final matches = _categories.where((item) => item.id == id);
    return matches.isEmpty ? 'Без категории' : matches.first.name;
  }

  String _accountName(String id) {
    if (id == LocalDatabase.unassignedAccountId) return 'Не указан';
    final matches = _accounts.where((item) => item.id == id);
    return matches.isEmpty ? 'Счёт' : matches.first.name;
  }

  double _balance(MoneyAccount account) {
    var value = account.initialBalance;
    for (final item in _transactions.where((item) =>
        item.currency == account.currency &&
        item.status == MoneyTransactionStatus.completed)) {
      if (item.accountId == account.id) {
        value += item.type == MoneyTransactionType.income
            ? item.amount
            : -item.amount;
      }
      if (item.type == MoneyTransactionType.transfer &&
          item.transferToAccountId == account.id) {
        value += item.amount;
      }
    }
    return value;
  }

  double _sum(MoneyTransactionType type, {bool? essential}) => _transactions
      .where((item) =>
          item.type == type &&
          item.status == MoneyTransactionStatus.completed &&
          (essential == null || item.essential == essential))
      .fold(0, (sum, item) => sum + item.amount);

  List<MoneyTransaction> get _visibleTransactions {
    final query = _query.trim().toLowerCase();
    return _transactions.where((item) {
      final filterMatches = _filter == 0 ||
          (_filter == 1 && item.type == MoneyTransactionType.income) ||
          (_filter == 2 && item.type == MoneyTransactionType.expense) ||
          (_filter == 3 && item.status != MoneyTransactionStatus.completed);
      final text =
          '${item.counterparty} ${item.purpose} ${_categoryName(item.categoryId)} ${_accountName(item.accountId)}'
              .toLowerCase();
      return filterMatches && (query.isEmpty || text.contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) => _PageScroll(
        child: ConstrainedBox(
          constraints: const BoxConstraints(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PageHeader(
                eyebrow: 'РАЗДЕЛ / ДЕНЬГИ',
                title: 'Деньги',
                description:
                    'Доходы, расходы, нал, карты и обязательства — в одной спокойной финансовой картине.',
                trailing: const _ModuleIcon(
                    icon: Icons.account_balance_wallet_outlined),
              ),
              const SizedBox(height: 18),
              _moneyTabs(),
              const SizedBox(height: 18),
              switch (_tab) {
                0 => _overview(),
                1 => _transactionsView(),
                2 => _accountsView(),
                3 => _obligationsView(),
                4 => _recurringView(),
                _ => _analyticsView(),
              },
            ],
          ),
        ),
      );

  Widget _moneyTabs() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            'Обзор',
            'Операции',
            'Счета',
            'Обязательства',
            'Регулярные',
            'Аналитика',
          ]
              .asMap()
              .entries
              .map((entry) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _tab == entry.key,
                      onSelected: (_) => setState(() => _tab = entry.key),
                      selectedColor: _amber,
                      backgroundColor: _elevated,
                      side: BorderSide(
                          color: _tab == entry.key ? _amber : _lineStrong),
                      labelStyle: TextStyle(
                        color: _tab == entry.key ? _base : _secondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ))
              .toList(),
        ),
      );

  Widget _metric(String label, String value, String note, IconData icon,
          {Color? color}) =>
      _HoverPanel(
        child: _HoverPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color ?? _primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(label.toUpperCase(),
                        style: TextStyle(
                            color: _tertiary,
                            fontFamily: 'Cascadia Mono',
                            fontSize: 9,
                            letterSpacing: .5)),
                    const SizedBox(height: 5),
                    Text(value,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color ?? _primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(note,
                        style: TextStyle(color: _secondary, fontSize: 11)),
                  ])),
            ],
          ),
        ),
      );

  List<_MoneyDayValue> _lastSevenDays() {
    final today = DateTime.now();
    return List.generate(7, (index) {
      final day = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: 6 - index));
      final key = day.toIso8601String().substring(0, 10);
      final value = _transactions
          .where((item) =>
              item.type == MoneyTransactionType.expense &&
              item.status == MoneyTransactionStatus.completed &&
              item.date == key)
          .fold<double>(0, (sum, item) => sum + item.amount);
      return _MoneyDayValue(
          label: const [
            'пн',
            'вт',
            'ср',
            'чт',
            'пт',
            'сб',
            'вс'
          ][day.weekday - 1],
          value: value);
    });
  }

  List<_MoneyCategoryValue> _topExpenseCategories() {
    final totals = <String, double>{};
    for (final item in _transactions.where((item) =>
        item.type == MoneyTransactionType.expense &&
        item.status == MoneyTransactionStatus.completed)) {
      totals.update(item.categoryId, (value) => value + item.amount,
          ifAbsent: () => item.amount);
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(4)
        .map((entry) => _MoneyCategoryValue(
            label: _categoryName(entry.key), value: entry.value))
        .toList();
  }

  Widget _overview() {
    final income = _sum(MoneyTransactionType.income);
    final expenses = _sum(MoneyTransactionType.expense);
    final available =
        _accounts.fold<double>(0, (sum, account) => sum + _balance(account));
    final planned = _transactions
        .where((item) => item.status != MoneyTransactionStatus.completed)
        .fold(0.0, (sum, item) => sum + item.amount);
    final obligations = _obligations
        .where((item) => item.status == 'active')
        .fold(0.0, (sum, item) => sum + item.totalAmount - item.paidAmount);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _HoverPanel(
        borderColor: _amberLine,
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(builder: (context, constraints) {
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelKicker(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'ДОСТУПНО СЕЙЧАС'),
              const SizedBox(height: 9),
              Text(_money(available),
                  style: TextStyle(
                      color: _primary,
                      fontSize: constraints.maxWidth < 500 ? 28 : 36,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text('Сумма остатков по вашим счетам',
                  style: TextStyle(color: _secondary)),
            ],
          );
          final flow = Wrap(
            spacing: 22,
            runSpacing: 10,
            children: [
              _MoneyInlineMetric(
                  label: 'Доходы', value: _money(income), color: _green),
              _MoneyInlineMetric(
                  label: 'Расходы', value: _money(expenses), color: _red),
              _MoneyInlineMetric(
                  label: 'Обязательства',
                  value: _money(obligations),
                  color: _amber),
            ],
          );
          if (constraints.maxWidth < 700) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [summary, const SizedBox(height: 18), flow]);
          }
          return Row(children: [
            Expanded(child: summary),
            const SizedBox(width: 24),
            Expanded(child: flow),
          ]);
        }),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
            onPressed: widget.onCapture,
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Записать одной фразой')),
        OutlinedButton.icon(
            onPressed: () => _openTransaction(),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Ручной ввод')),
        TextButton.icon(
            onPressed: _openOpeningBalances,
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Счета и остатки')),
      ]),
      if (_transactions.isEmpty && available == 0) ...[
        const SizedBox(height: 12),
        _HoverPanel(
          color: _elevated,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Три шага — и финансовая картина начнёт работать',
                  style:
                      TextStyle(color: _primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const _MoneySetupStep(
                  number: '1',
                  title: 'Укажите реальные остатки',
                  detail: 'Сколько сейчас в кошельке и на картах.'),
              const _MoneySetupStep(
                  number: '2',
                  title: 'Добавьте первую операцию',
                  detail: 'Фразой или через обычную форму.'),
              const _MoneySetupStep(
                  number: '3',
                  title: 'Получайте аналитику',
                  detail: 'Графики появятся, когда в них будут ваши данные.'),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: _openOpeningBalances,
                  child: const Text('Указать остатки')),
            ],
          ),
        ),
      ],
      if (_transactions.isNotEmpty) ...[
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          final charts = [
            _MoneyWeeklyChart(values: _lastSevenDays(), formatMoney: _money),
            _MoneyCategoryChart(
                values: _topExpenseCategories(), formatMoney: _money),
          ];
          if (constraints.maxWidth >= 760) {
            return Row(children: [
              Expanded(child: charts[0]),
              const SizedBox(width: 12),
              Expanded(child: charts[1]),
            ]);
          }
          return Column(
              children: [charts[0], const SizedBox(height: 12), charts[1]]);
        }),
      ],
      if (planned > 0 || obligations > 0) ...[
        const SizedBox(height: 14),
        _HoverPanel(
          borderColor: _amberLine,
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            Icon(Icons.info_outline, color: _amber, size: 19),
            const SizedBox(width: 11),
            Expanded(
                child: Text(
                    'Запланировано: ${_money(planned)} · обязательств осталось: ${_money(obligations)}',
                    style: TextStyle(color: _secondary, fontSize: 13))),
          ]),
        ),
      ],
      const SizedBox(height: 22),
      _SectionHeader(
          eyebrow: 'СЧЕТА',
          title: 'Где лежат деньги',
          trailing: Text(_accountsCountLabel(_accounts.length),
              style: TextStyle(
                  color: _tertiary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 10))),
      const SizedBox(height: 11),
      if (_accounts.isEmpty)
        Text('Добавьте первый счёт', style: TextStyle(color: _secondary))
      else
        Wrap(
            spacing: 10,
            runSpacing: 10,
            children:
                _accounts.map((account) => _accountCard(account)).toList()),
      const SizedBox(height: 22),
      _SectionHeader(
          eyebrow: 'ПОСЛЕДНИЕ ОПЕРАЦИИ',
          title: 'История',
          trailing: TextButton(
              onPressed: () => setState(() => _tab = 1),
              child: Text('ВСЕ ОПЕРАЦИИ'))),
      const SizedBox(height: 10),
      if (_transactions.isEmpty)
        _EmptyState(name: 'деньги', onCapture: () => _openTransaction())
      else
        ..._transactions.take(8).map(_transactionTile),
    ]);
  }

  String _accountsCountLabel(int value) {
    final tail = value % 100;
    if (tail >= 11 && tail <= 14) return '$value СЧЕТОВ';
    return switch (value % 10) {
      1 => '$value СЧЁТ',
      2 || 3 || 4 => '$value СЧЁТА',
      _ => '$value СЧЕТОВ',
    };
  }

  Widget _transactionsView() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Найти по назначению, категории или счёту'),
                  onChanged: (value) => setState(() => _query = value))),
          const SizedBox(width: 10),
          FilledButton.icon(
              onPressed: () => _openTransaction(),
              icon: Icon(Icons.add),
              label: Text('Добавить')),
        ]),
        const SizedBox(height: 12),
        Wrap(
            spacing: 8,
            children: ['Все', 'Доходы', 'Расходы', 'Планы']
                .asMap()
                .entries
                .map((entry) => ChoiceChip(
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    onSelected: (_) => setState(() => _filter = entry.key)))
                .toList()),
        const SizedBox(height: 14),
        if (_visibleTransactions.isEmpty)
          _EmptyState(name: 'операции', onCapture: () => _openTransaction())
        else
          ..._visibleTransactions.map(_transactionTile),
      ]);

  Widget _transactionTile(MoneyTransaction item) {
    final income = item.type == MoneyTransactionType.income;
    final transfer = item.type == MoneyTransactionType.transfer;
    final color = transfer
        ? _amber
        : income
            ? _green
            : _red;
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _HoverPanel(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            child: Row(children: [
              Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: color.withOpacity(.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(
                      transfer
                          ? Icons.swap_horiz
                          : income
                              ? Icons.south_west
                              : Icons.north_east,
                      color: color,
                      size: 18)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        item.purpose.isNotEmpty
                            ? item.purpose
                            : (item.counterparty.isNotEmpty
                                ? item.counterparty
                                : _categoryName(item.categoryId)),
                        style: TextStyle(
                            color: _primary, fontWeight: FontWeight.w700)),
                    SizedBox(height: 3),
                    Text(
                        '${item.date} · ${_categoryName(item.categoryId)} · ${_accountName(item.accountId)}${item.status == MoneyTransactionStatus.completed ? '' : ' · ${_moneyStatus(item.status)}'}',
                        style: TextStyle(color: _secondary, fontSize: 11))
                  ])),
              Text(
                  '${income ? '+' : transfer ? '↔' : '-'}${_money(item.amount, item.currency)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'delete') {
                      await _deleteTransaction(item);
                    } else if (value == 'duplicate') {
                      await widget.database.saveMoneyTransaction(
                          MoneyTransaction(
                              id: '${DateTime.now().microsecondsSinceEpoch}',
                              date: item.date,
                              type: item.type,
                              amount: item.amount,
                              currency: item.currency,
                              counterparty: item.counterparty,
                              categoryId: item.categoryId,
                              purpose: item.purpose,
                              paymentMethod: item.paymentMethod,
                              accountId: item.accountId,
                              transferToAccountId: item.transferToAccountId,
                              recurring: item.recurring,
                              status: item.status,
                              incomeSource: item.incomeSource,
                              obligationId: item.obligationId,
                              essential: item.essential,
                              comment: item.comment,
                              createdAt: DateTime.now()));
                      _reload();
                    } else {
                      _openTransaction(existing: item);
                    }
                  },
                  itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Изменить')),
                        PopupMenuItem(
                            value: 'duplicate', child: Text('Дублировать')),
                        PopupMenuItem(value: 'delete', child: Text('Удалить'))
                      ]),
            ])));
  }

  String _moneyStatus(MoneyTransactionStatus status) => switch (status) {
        MoneyTransactionStatus.planned => 'план',
        MoneyTransactionStatus.expected => 'ожидается',
        _ => 'готово'
      };

  Widget _accountCard(MoneyAccount account) => SizedBox(
      width: 235,
      child: _HoverPanel(
          padding: EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(
                  account.type == MoneyAccountType.cash
                      ? Icons.payments_outlined
                      : account.type == MoneyAccountType.card
                          ? Icons.credit_card_outlined
                          : Icons.account_balance_outlined,
                  color: _amber,
                  size: 20),
              SizedBox(width: 8),
              Expanded(
                  child: Text(account.name,
                      style: TextStyle(
                          color: _primary, fontWeight: FontWeight.w700))),
              Text(account.currency,
                  style: TextStyle(
                      color: _tertiary,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 10))
            ]),
            SizedBox(height: 14),
            Text(_money(_balance(account), account.currency),
                style: TextStyle(
                    color: _primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text(_accountType(account.type),
                style: TextStyle(color: _secondary, fontSize: 11))
          ])));

  String _accountType(MoneyAccountType type) => switch (type) {
        MoneyAccountType.cash => 'наличные',
        MoneyAccountType.card => 'банковская карта',
        MoneyAccountType.bank => 'банковский счёт',
        MoneyAccountType.wallet => 'электронный кошелёк'
      };

  Widget _accountsView() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('Счета и способы оплаты',
                  style: TextStyle(
                      color: _primary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700))),
          FilledButton.icon(
              onPressed: _openAccount,
              icon: Icon(Icons.add),
              label: Text('Новый счёт'))
        ]),
        const SizedBox(height: 12),
        Text(
            'Баланс считается по завершённым операциям. Плановые записи не меняют фактический остаток.',
            style: TextStyle(color: _secondary, fontSize: 12)),
        const SizedBox(height: 14),
        Wrap(
            spacing: 10,
            runSpacing: 10,
            children:
                _accounts.map((account) => _accountCard(account)).toList()),
      ]);

  Widget _obligationsView() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('Обязательства и крупные платежи',
                  style: TextStyle(
                      color: _primary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700))),
          FilledButton.icon(
              onPressed: _openObligation,
              icon: Icon(Icons.add),
              label: Text('Добавить'))
        ]),
        const SizedBox(height: 14),
        if (_obligations.isEmpty)
          _EmptyState(name: 'обязательства', onCapture: _openObligation)
        else
          ..._obligations.map((item) {
            final progress = item.totalAmount == 0
                ? 0.0
                : (item.paidAmount / item.totalAmount).clamp(0.0, 1.0);
            return Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: _HoverPanel(
                    padding: EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(item.name,
                                    style: TextStyle(
                                        color: _primary,
                                        fontWeight: FontWeight.w700))),
                            Text(
                                '${_money(item.totalAmount - item.paidAmount, item.currency)} осталось',
                                style: TextStyle(
                                    color: _amber,
                                    fontWeight: FontWeight.w700)),
                            PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'delete') {
                                    await _deleteObligation(item);
                                  }
                                },
                                itemBuilder: (_) => [
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Удалить'))
                                    ])
                          ]),
                          SizedBox(height: 9),
                          ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 7,
                                  color: _amber,
                                  backgroundColor: _lineStrong)),
                          SizedBox(height: 7),
                          Text(
                              '${_money(item.paidAmount, item.currency)} оплачено · срок ${item.dueDate}${item.recurrence == null ? '' : ' · ${_recurrence(item.recurrence!)}'}',
                              style: TextStyle(color: _secondary, fontSize: 11))
                        ])));
          }),
      ]);

  Widget _recurringView() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('Регулярные доходы и расходы',
                  style: TextStyle(
                      color: _primary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700))),
          FilledButton.icon(
              onPressed: _openRecurring,
              icon: Icon(Icons.add),
              label: Text('Новый шаблон'))
        ]),
        const SizedBox(height: 14),
        if (_recurring.isEmpty)
          _EmptyState(name: 'регулярные операции', onCapture: _openRecurring)
        else
          ..._recurring.map((item) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: _HoverPanel(
                  padding: EdgeInsets.all(15),
                  child: Row(children: [
                    Icon(
                        item.type == MoneyTransactionType.income
                            ? Icons.autorenew
                            : Icons.repeat,
                        color: item.type == MoneyTransactionType.income
                            ? _green
                            : _amber),
                    SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(item.name,
                              style: TextStyle(
                                  color: _primary,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 3),
                          Text(
                              '${_recurrence(item.recurrence)} · следующая дата ${item.nextDate} · ${_accountName(item.accountId)}',
                              style: TextStyle(color: _secondary, fontSize: 11))
                        ])),
                    Text(_money(item.amount, item.currency),
                        style: TextStyle(
                            color: _primary, fontWeight: FontWeight.w700)),
                    PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'delete') {
                            await _deleteRecurring(item);
                          }
                        },
                        itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'delete', child: Text('Удалить'))
                            ])
                  ])))),
      ]);

  String _recurrence(MoneyRecurrence value) => switch (value) {
        MoneyRecurrence.weekly => 'еженедельно',
        MoneyRecurrence.monthly => 'ежемесячно',
        MoneyRecurrence.quarterly => 'ежеквартально',
        MoneyRecurrence.yearly => 'ежегодно'
      };

  Widget _analyticsView() {
    final expenses = _transactions
        .where((item) =>
            item.type == MoneyTransactionType.expense &&
            item.status == MoneyTransactionStatus.completed)
        .toList();
    final byCategory = <String, double>{};
    for (final item in expenses) {
      byCategory[item.categoryId] =
          (byCategory[item.categoryId] ?? 0) + item.amount;
    }
    final sorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = expenses.fold(0.0, (sum, item) => sum + item.amount);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: _metric('Общие расходы', _money(total),
                'завершённые операции', Icons.analytics_outlined,
                color: _red)),
        SizedBox(width: 10),
        Expanded(
            child: _metric(
                'Необходимые',
                _money(_sum(MoneyTransactionType.expense, essential: true)),
                'без необязательных',
                Icons.check_circle_outline,
                color: _green)),
        SizedBox(width: 10),
        Expanded(
            child: _metric(
                'Необязательные',
                _money(_sum(MoneyTransactionType.expense, essential: false)),
                'что можно пересмотреть',
                Icons.tune_outlined,
                color: _amber))
      ]),
      const SizedBox(height: 22),
      _SectionHeader(
          eyebrow: 'РАСХОДЫ ПО КАТЕГОРИЯМ', title: 'Куда уходят деньги'),
      const SizedBox(height: 12),
      if (sorted.isEmpty)
        Text('Добавьте несколько расходов — здесь появится структура.',
            style: TextStyle(color: _secondary))
      else
        ...sorted.take(10).map((entry) {
          final ratio = total == 0 ? 0.0 : entry.value / total;
          return Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: Text(_categoryName(entry.key),
                          style: TextStyle(color: _primary, fontSize: 13))),
                  Text(_money(entry.value),
                      style: TextStyle(color: _secondary, fontSize: 12))
                ]),
                SizedBox(height: 5),
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        color: _amber,
                        backgroundColor: _lineStrong))
              ]));
        }),
    ]);
  }

  Future<void> _openTransaction({MoneyTransaction? existing}) async {
    final result = await showDialog<MoneyTransaction>(
        context: context,
        builder: (_) => _MoneyTransactionDialog(
            existing: existing, accounts: _accounts, categories: _categories));
    if (result != null) {
      await widget.database.saveMoneyTransaction(result);
      _reload();
    }
  }

  Future<bool> _confirmDelete(String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Удалить запись?'),
            content: Text(
              '«$title» исчезнет из расчётов. Сразу после удаления её можно будет восстановить.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Оставить'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteTransaction(MoneyTransaction item) async {
    final title = item.purpose.isNotEmpty
        ? item.purpose
        : item.counterparty.isNotEmpty
            ? item.counterparty
            : _categoryName(item.categoryId);
    if (!await _confirmDelete(title)) return;
    await widget.database.deleteMoneyTransaction(item.id);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Операция удалена'),
        action: SnackBarAction(
          label: 'Восстановить',
          onPressed: () async {
            await widget.database.saveMoneyTransaction(item);
            if (mounted) _reload();
          },
        ),
      ),
    );
  }

  Future<void> _deleteObligation(MoneyObligation item) async {
    if (!await _confirmDelete(item.name)) return;
    await widget.database.deleteMoneyObligation(item.id);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Обязательство удалено'),
        action: SnackBarAction(
          label: 'Восстановить',
          onPressed: () async {
            await widget.database.saveMoneyObligation(item);
            if (mounted) _reload();
          },
        ),
      ),
    );
  }

  Future<void> _deleteRecurring(MoneyRecurringTemplate item) async {
    if (!await _confirmDelete(item.name)) return;
    await widget.database.deleteMoneyRecurring(item.id);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Регулярная операция удалена'),
        action: SnackBarAction(
          label: 'Восстановить',
          onPressed: () async {
            await widget.database.saveMoneyRecurring(item);
            if (mounted) _reload();
          },
        ),
      ),
    );
  }

  Future<void> _openAccount() async {
    final result = await showDialog<MoneyAccount>(
        context: context, builder: (_) => const _MoneyAccountDialog());
    if (result != null) {
      await widget.database.saveMoneyAccount(result);
      _reload();
    }
  }

  Future<void> _openOpeningBalances() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MoneyOpeningBalancesDialog(
        database: widget.database,
        accounts: _accounts,
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _openObligation() async {
    final result = await showDialog<MoneyObligation>(
        context: context, builder: (_) => const _MoneyObligationDialog());
    if (result != null) {
      await widget.database.saveMoneyObligation(result);
      _reload();
    }
  }

  Future<void> _openRecurring() async {
    final result = await showDialog<MoneyRecurringTemplate>(
        context: context,
        builder: (_) => _MoneyRecurringDialog(
            accounts: _accounts, categories: _categories));
    if (result != null) {
      await widget.database.saveMoneyRecurring(result);
      _reload();
    }
  }
}

class _MoneyDayValue {
  const _MoneyDayValue({required this.label, required this.value});
  final String label;
  final double value;
}

class _MoneyCategoryValue {
  const _MoneyCategoryValue({required this.label, required this.value});
  final String label;
  final double value;
}

class _MoneySetupStep extends StatelessWidget {
  const _MoneySetupStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _amber.withAlpha(24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(number,
                  style: TextStyle(color: _amber, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: '$title — ',
                        style: TextStyle(
                            color: _primary, fontWeight: FontWeight.w700)),
                    TextSpan(text: detail, style: TextStyle(color: _secondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _MoneyInlineMetric extends StatelessWidget {
  const _MoneyInlineMetric(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: _tertiary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 9,
                  letterSpacing: .5)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      );
}

class _MoneyWeeklyChart extends StatelessWidget {
  const _MoneyWeeklyChart({required this.values, required this.formatMoney});
  final List<_MoneyDayValue> values;
  final String Function(num) formatMoney;

  @override
  Widget build(BuildContext context) {
    final maxValue =
        values.fold<double>(0, (maximum, item) => max(maximum, item.value));
    final total = values.fold<double>(0, (sum, item) => sum + item.value);
    return _HoverPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
                child: _PanelKicker(
                    icon: Icons.bar_chart_rounded, label: 'РАСХОДЫ · 7 ДНЕЙ')),
            Text(formatMoney(total),
                style: TextStyle(color: _primary, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 112,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values.map((item) {
                final ratio = maxValue == 0 ? 0.06 : item.value / maxValue;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: ratio.clamp(.06, 1.0).toDouble(),
                              widthFactor: .65,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: item.value == 0
                                      ? _lineStrong
                                      : _amber.withAlpha(190),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(item.label,
                            style: TextStyle(
                                color: _tertiary,
                                fontSize: 10,
                                fontFamily: 'Cascadia Mono')),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyCategoryChart extends StatelessWidget {
  const _MoneyCategoryChart({required this.values, required this.formatMoney});
  final List<_MoneyCategoryValue> values;
  final String Function(num) formatMoney;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.isEmpty
        ? 0.0
        : values.fold<double>(0, (maximum, item) => max(maximum, item.value));
    return _HoverPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelKicker(
              icon: Icons.donut_small_rounded, label: 'КУДА УХОДЯТ ДЕНЬГИ'),
          const SizedBox(height: 14),
          if (values.isEmpty)
            SizedBox(
              height: 114,
              child: Center(
                child: Text('Категории появятся после первых расходов',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _secondary, fontSize: 12)),
              ),
            )
          else
            ...values.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(item.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: _secondary, fontSize: 12))),
                        const SizedBox(width: 8),
                        Text(formatMoney(item.value),
                            style: TextStyle(
                                color: _primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: maxValue == 0 ? 0 : item.value / maxValue,
                          minHeight: 7,
                          color: _amber,
                          backgroundColor: _lineStrong,
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _MoneyOpeningBalancesDialog extends StatefulWidget {
  const _MoneyOpeningBalancesDialog({
    required this.database,
    required this.accounts,
  });

  final LocalDatabase database;
  final List<MoneyAccount> accounts;

  @override
  State<_MoneyOpeningBalancesDialog> createState() =>
      _MoneyOpeningBalancesDialogState();
}

class _MoneyOpeningBalancesDialogState
    extends State<_MoneyOpeningBalancesDialog> {
  final names = <String, TextEditingController>{};
  final balances = <String, TextEditingController>{};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    for (final account in widget.accounts) {
      names[account.id] = TextEditingController(text: account.name);
      balances[account.id] = TextEditingController(
          text: account.initialBalance == 0
              ? ''
              : account.initialBalance
                  .toStringAsFixed(account.currency == 'USD' ? 2 : 0));
    }
  }

  @override
  void dispose() {
    for (final controller in [...names.values, ...balances.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => busy = true);
    for (final account in widget.accounts) {
      final name = names[account.id]!.text.trim();
      final balance = double.tryParse(balances[account.id]!
              .text
              .replaceAll(' ', '')
              .replaceAll(',', '.')) ??
          0;
      await widget.database.saveMoneyAccount(MoneyAccount(
        id: account.id,
        name: name.isEmpty ? account.name : name,
        type: account.type,
        currency: account.currency,
        initialBalance: balance,
        color: account.color,
        createdAt: account.createdAt,
      ));
    }
    await widget.database.savePreference('money.setupCompleted', true);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Счета и стартовые остатки'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Укажите, сколько денег находится на каждом счёте прямо сейчас. Это не будет записано как доход.'),
                const SizedBox(height: 14),
                ...widget.accounts.map((account) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: names[account.id],
                            decoration:
                                const InputDecoration(labelText: 'Название'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: balances[account.id],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: 'Остаток · ${account.currency}'),
                          ),
                        ),
                      ]),
                    )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: busy ? null : _save,
              child: Text(busy ? 'Сохраняем…' : 'Сохранить остатки')),
        ],
      );
}

class _MoneyTransactionDialog extends StatefulWidget {
  const _MoneyTransactionDialog(
      {this.existing, required this.accounts, required this.categories});
  final MoneyTransaction? existing;
  final List<MoneyAccount> accounts;
  final List<MoneyCategory> categories;
  @override
  State<_MoneyTransactionDialog> createState() =>
      _MoneyTransactionDialogState();
}

class _MoneyTransactionDialogState extends State<_MoneyTransactionDialog> {
  late final TextEditingController amount;
  late final TextEditingController purpose;
  late final TextEditingController counterparty;
  late final TextEditingController comment;
  late String date, currency, accountId, categoryId;
  String? transferToAccountId;
  late MoneyTransactionType type;
  late MoneyPaymentMethod payment;
  late MoneyTransactionStatus status;
  bool essential = true, recurring = false;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    amount =
        TextEditingController(text: item == null ? '' : item.amount.toString());
    purpose = TextEditingController(text: item?.purpose ?? '');
    counterparty = TextEditingController(text: item?.counterparty ?? '');
    comment = TextEditingController(text: item?.comment ?? '');
    type = item?.type ?? MoneyTransactionType.expense;
    currency = item?.currency ?? 'UZS';
    accountId = item?.accountId ?? widget.accounts.first.id;
    transferToAccountId = item?.transferToAccountId ??
        (widget.accounts.length > 1 ? widget.accounts[1].id : null);
    categoryId = item?.categoryId ??
        widget.categories
            .where((c) => c.kind == MoneyCategoryKind.expense)
            .first
            .id;
    payment = item?.paymentMethod ?? MoneyPaymentMethod.card;
    status = item?.status ?? MoneyTransactionStatus.completed;
    date = item?.date ?? DateTime.now().toIso8601String().substring(0, 10);
    essential = item?.essential ?? true;
    recurring = item?.recurring ?? false;
  }

  @override
  void dispose() {
    amount.dispose();
    purpose.dispose();
    counterparty.dispose();
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories
        .where((c) => type == MoneyTransactionType.income
            ? c.kind == MoneyCategoryKind.income
            : c.kind == MoneyCategoryKind.expense)
        .toList();
    final safeCategory = categories.any((c) => c.id == categoryId)
        ? categoryId
        : categories.first.id;
    if (safeCategory != categoryId) categoryId = safeCategory;
    return AlertDialog(
      title: Text(
          widget.existing == null ? 'Новая операция' : 'Изменить операцию'),
      content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<MoneyTransactionType>(
                segments: const [
                  ButtonSegment(
                      value: MoneyTransactionType.expense,
                      label: Text('Расход')),
                  ButtonSegment(
                      value: MoneyTransactionType.income, label: Text('Доход')),
                  ButtonSegment(
                      value: MoneyTransactionType.transfer,
                      label: Text('Перевод'))
                ],
                selected: {
                  type
                },
                onSelectionChanged: (v) => setState(() {
                      type = v.first;
                    })),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Сумма',
                          prefixIcon: Icon(Icons.payments_outlined)))),
              const SizedBox(width: 10),
              SizedBox(
                  width: 112,
                  child: DropdownButtonFormField<String>(
                      value: currency,
                      decoration: const InputDecoration(labelText: 'Валюта'),
                      items: const [
                        DropdownMenuItem(value: 'UZS', child: Text('UZS')),
                        DropdownMenuItem(value: 'USD', child: Text('USD'))
                      ],
                      onChanged: (v) => setState(() => currency = v ?? 'UZS')))
            ]),
            const SizedBox(height: 10),
            TextField(
                controller: purpose,
                decoration: const InputDecoration(
                    labelText: 'Назначение',
                    hintText: 'Например, продукты на неделю',
                    prefixIcon: Icon(Icons.edit_note_outlined))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: DropdownButtonFormField<String>(
                      value: categoryId,
                      decoration: const InputDecoration(labelText: 'Категория'),
                      items: categories
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => categoryId = v ?? categoryId))),
              const SizedBox(width: 10),
              Expanded(
                  child: DropdownButtonFormField<String>(
                      value: accountId,
                      decoration: const InputDecoration(labelText: 'Счёт'),
                      items: widget.accounts
                          .map((a) => DropdownMenuItem(
                              value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => accountId = v ?? accountId)))
            ]),
            if (type == MoneyTransactionType.transfer &&
                widget.accounts.length > 1) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                  value: transferToAccountId,
                  decoration:
                      const InputDecoration(labelText: 'Перевести на счёт'),
                  items: widget.accounts
                      .where((a) => a.id != accountId)
                      .map((a) =>
                          DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => transferToAccountId = v))
            ],
            if (type != MoneyTransactionType.transfer) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: DropdownButtonFormField<MoneyPaymentMethod>(
                        value: payment,
                        decoration:
                            const InputDecoration(labelText: 'Способ оплаты'),
                        items: const [
                          DropdownMenuItem(
                              value: MoneyPaymentMethod.cash,
                              child: Text('Наличные')),
                          DropdownMenuItem(
                              value: MoneyPaymentMethod.card,
                              child: Text('Карта')),
                          DropdownMenuItem(
                              value: MoneyPaymentMethod.bank,
                              child: Text('Банк')),
                          DropdownMenuItem(
                              value: MoneyPaymentMethod.other,
                              child: Text('Другое'))
                        ],
                        onChanged: (v) =>
                            setState(() => payment = v ?? payment))),
                const SizedBox(width: 10),
                Expanded(
                    child: DropdownButtonFormField<MoneyTransactionStatus>(
                        value: status,
                        decoration: const InputDecoration(labelText: 'Статус'),
                        items: const [
                          DropdownMenuItem(
                              value: MoneyTransactionStatus.completed,
                              child: Text('Завершено')),
                          DropdownMenuItem(
                              value: MoneyTransactionStatus.planned,
                              child: Text('Запланировано')),
                          DropdownMenuItem(
                              value: MoneyTransactionStatus.expected,
                              child: Text('Ожидается'))
                        ],
                        onChanged: (v) => setState(() => status = v ?? status)))
              ]),
            ],
            const SizedBox(height: 10),
            TextField(
                decoration: const InputDecoration(
                    labelText: 'Дата',
                    prefixIcon: Icon(Icons.calendar_today_outlined)),
                controller: TextEditingController(text: date),
                onChanged: (v) => date = v),
            const SizedBox(height: 4),
            TextField(
                controller: counterparty,
                decoration: const InputDecoration(
                    labelText: 'Кому / от кого',
                    prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 4),
            TextField(
                controller: comment,
                decoration: const InputDecoration(labelText: 'Комментарий')),
            CheckboxListTile(
                value: essential,
                onChanged: (v) => setState(() => essential = v ?? true),
                title: Text('Необходимая операция'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading),
            CheckboxListTile(
                value: recurring,
                onChanged: (v) => setState(() => recurring = v ?? false),
                title: Text('Повторяется регулярно'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading),
          ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text('Отмена')),
        FilledButton(onPressed: _save, child: Text('Сохранить'))
      ],
    );
  }

  void _save() {
    final parsed =
        double.tryParse(amount.text.replaceAll(' ', '').replaceAll(',', '.'));
    if (parsed == null || parsed <= 0 || purpose.text.trim().isEmpty) return;
    Navigator.pop(
        context,
        MoneyTransaction(
            id: widget.existing?.id ??
                '${DateTime.now().microsecondsSinceEpoch}',
            date: date.trim().isEmpty
                ? DateTime.now().toIso8601String().substring(0, 10)
                : date.trim(),
            type: type,
            amount: parsed,
            currency: currency,
            counterparty: counterparty.text.trim(),
            categoryId: categoryId,
            purpose: purpose.text.trim(),
            paymentMethod: payment,
            accountId: accountId,
            transferToAccountId: type == MoneyTransactionType.transfer
                ? transferToAccountId
                : null,
            recurring: recurring,
            status: status,
            essential: essential,
            comment: comment.text.trim(),
            createdAt: widget.existing?.createdAt ?? DateTime.now()));
  }
}

class _MoneyAccountDialog extends StatefulWidget {
  const _MoneyAccountDialog();
  @override
  State<_MoneyAccountDialog> createState() => _MoneyAccountDialogState();
}

class _MoneyAccountDialogState extends State<_MoneyAccountDialog> {
  final name = TextEditingController();
  final balance = TextEditingController();
  MoneyAccountType type = MoneyAccountType.card;
  String currency = 'UZS';
  @override
  void dispose() {
    name.dispose();
    balance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text('Новый счёт'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                decoration: InputDecoration(
                    labelText: 'Название', hintText: 'Например, Карта Uzcard')),
            SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: DropdownButtonFormField<MoneyAccountType>(
                      value: type,
                      decoration: InputDecoration(labelText: 'Тип'),
                      items: [
                        DropdownMenuItem(
                            value: MoneyAccountType.cash,
                            child: Text('Наличные')),
                        DropdownMenuItem(
                            value: MoneyAccountType.card, child: Text('Карта')),
                        DropdownMenuItem(
                            value: MoneyAccountType.bank, child: Text('Банк')),
                        DropdownMenuItem(
                            value: MoneyAccountType.wallet,
                            child: Text('Кошелёк'))
                      ],
                      onChanged: (v) => setState(() => type = v ?? type))),
              SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: balance,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: 'Стартовый баланс')))
            ]),
            SizedBox(height: 10),
            DropdownButtonFormField<String>(
                value: currency,
                decoration: InputDecoration(labelText: 'Валюта'),
                items: [
                  DropdownMenuItem(value: 'UZS', child: Text('UZS')),
                  DropdownMenuItem(value: 'USD', child: Text('USD'))
                ],
                onChanged: (v) => setState(() => currency = v ?? currency))
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text('Отмена')),
            FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) return;
                  Navigator.pop(
                      context,
                      MoneyAccount(
                          id: '${DateTime.now().microsecondsSinceEpoch}',
                          name: name.text.trim(),
                          type: type,
                          currency: currency,
                          initialBalance: double.tryParse(
                                  balance.text.replaceAll(',', '.')) ??
                              0,
                          color: '#F0B429',
                          createdAt: DateTime.now()));
                },
                child: Text('Сохранить'))
          ]);
}

class _MoneyObligationDialog extends StatefulWidget {
  const _MoneyObligationDialog();
  @override
  State<_MoneyObligationDialog> createState() => _MoneyObligationDialogState();
}

class _MoneyObligationDialogState extends State<_MoneyObligationDialog> {
  final name = TextEditingController();
  final total = TextEditingController();
  final paid = TextEditingController();
  final due = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  String currency = 'UZS';
  MoneyRecurrence? recurrence;
  @override
  void dispose() {
    name.dispose();
    total.dispose();
    paid.dispose();
    due.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text('Новое обязательство'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                decoration: InputDecoration(labelText: 'Что нужно оплатить')),
            SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: total,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Всего'))),
              SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: paid,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Уже оплачено')))
            ]),
            SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: due,
                      decoration: InputDecoration(labelText: 'Срок'))),
              SizedBox(width: 8),
              Expanded(
                  child: DropdownButtonFormField<String>(
                      value: currency,
                      decoration: InputDecoration(labelText: 'Валюта'),
                      items: [
                        DropdownMenuItem(value: 'UZS', child: Text('UZS')),
                        DropdownMenuItem(value: 'USD', child: Text('USD'))
                      ],
                      onChanged: (v) =>
                          setState(() => currency = v ?? currency)))
            ]),
            SizedBox(height: 8),
            DropdownButtonFormField<MoneyRecurrence?>(
                value: recurrence,
                decoration: InputDecoration(labelText: 'Повторение'),
                items: [
                  DropdownMenuItem(value: null, child: Text('Разово')),
                  DropdownMenuItem(
                      value: MoneyRecurrence.monthly,
                      child: Text('Ежемесячно')),
                  DropdownMenuItem(
                      value: MoneyRecurrence.quarterly,
                      child: Text('Ежеквартально')),
                  DropdownMenuItem(
                      value: MoneyRecurrence.yearly, child: Text('Ежегодно'))
                ],
                onChanged: (v) => setState(() => recurrence = v))
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: Text('Отмена')),
            FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty ||
                      double.tryParse(total.text.replaceAll(',', '.')) == null)
                    return;
                  final value = double.parse(total.text.replaceAll(',', '.'));
                  Navigator.pop(
                      context,
                      MoneyObligation(
                          id: '${DateTime.now().microsecondsSinceEpoch}',
                          name: name.text.trim(),
                          totalAmount: value,
                          paidAmount:
                              double.tryParse(paid.text.replaceAll(',', '.')) ??
                                  0,
                          currency: currency,
                          dueDate: due.text.trim(),
                          recurrence: recurrence,
                          comment: '',
                          status: 'active'));
                },
                child: Text('Сохранить'))
          ]);
}

class _MoneyRecurringDialog extends StatefulWidget {
  const _MoneyRecurringDialog(
      {required this.accounts, required this.categories});
  final List<MoneyAccount> accounts;
  final List<MoneyCategory> categories;
  @override
  State<_MoneyRecurringDialog> createState() => _MoneyRecurringDialogState();
}

class _MoneyRecurringDialogState extends State<_MoneyRecurringDialog> {
  final name = TextEditingController();
  final amount = TextEditingController();
  final nextDate = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  MoneyTransactionType type = MoneyTransactionType.expense;
  MoneyRecurrence recurrence = MoneyRecurrence.monthly;
  late String accountId, categoryId;
  @override
  void initState() {
    super.initState();
    accountId = widget.accounts.first.id;
    categoryId = widget.categories
        .firstWhere((c) => c.kind == MoneyCategoryKind.expense)
        .id;
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    nextDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories
        .where((c) =>
            c.kind ==
            (type == MoneyTransactionType.income
                ? MoneyCategoryKind.income
                : MoneyCategoryKind.expense))
        .toList();
    if (!categories.any((c) => c.id == categoryId))
      categoryId = categories.first.id;
    return AlertDialog(
        title: Text('Регулярный шаблон'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: InputDecoration(
                  labelText: 'Название',
                  hintText: 'Аренда, подписка, зарплата')),
          SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Сумма'))),
            SizedBox(width: 8),
            Expanded(
                child: DropdownButtonFormField<MoneyTransactionType>(
                    value: type,
                    decoration: InputDecoration(labelText: 'Тип'),
                    items: [
                      DropdownMenuItem(
                          value: MoneyTransactionType.expense,
                          child: Text('Расход')),
                      DropdownMenuItem(
                          value: MoneyTransactionType.income,
                          child: Text('Доход'))
                    ],
                    onChanged: (v) => setState(() => type = v ?? type)))
          ]),
          SizedBox(height: 8),
          DropdownButtonFormField<String>(
              value: categoryId,
              decoration: InputDecoration(labelText: 'Категория'),
              items: categories
                  .map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => categoryId = v ?? categoryId)),
          SizedBox(height: 8),
          DropdownButtonFormField<String>(
              value: accountId,
              decoration: InputDecoration(labelText: 'Счёт'),
              items: widget.accounts
                  .map(
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                  .toList(),
              onChanged: (v) => setState(() => accountId = v ?? accountId)),
          SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: nextDate,
                    decoration: InputDecoration(labelText: 'Следующая дата'))),
            SizedBox(width: 8),
            Expanded(
                child: DropdownButtonFormField<MoneyRecurrence>(
                    value: recurrence,
                    decoration: InputDecoration(labelText: 'Период'),
                    items: [
                      DropdownMenuItem(
                          value: MoneyRecurrence.weekly,
                          child: Text('Еженедельно')),
                      DropdownMenuItem(
                          value: MoneyRecurrence.monthly,
                          child: Text('Ежемесячно')),
                      DropdownMenuItem(
                          value: MoneyRecurrence.quarterly,
                          child: Text('Ежеквартально')),
                      DropdownMenuItem(
                          value: MoneyRecurrence.yearly,
                          child: Text('Ежегодно'))
                    ],
                    onChanged: (v) =>
                        setState(() => recurrence = v ?? recurrence)))
          ])
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('Отмена')),
          FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text.replaceAll(',', '.'));
                if (name.text.trim().isEmpty || value == null || value <= 0)
                  return;
                Navigator.pop(
                    context,
                    MoneyRecurringTemplate(
                        id: '${DateTime.now().microsecondsSinceEpoch}',
                        name: name.text.trim(),
                        type: type,
                        amount: value,
                        currency: 'UZS',
                        counterparty: '',
                        categoryId: categoryId,
                        accountId: accountId,
                        nextDate: nextDate.text.trim(),
                        recurrence: recurrence,
                        status: 'active'));
              },
              child: Text('Сохранить'))
        ]);
  }
}

class _ModuleMetrics extends StatelessWidget {
  const _ModuleMetrics({
    required this.records,
    required this.today,
    required this.pending,
    required this.lastDate,
  });

  final int records;
  final int today;
  final int pending;
  final String lastDate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final cards = [
            ('Записей', '$records', 'в этом разделе', Icons.list_alt_outlined),
            ('Сегодня', '$today', 'за текущий день', Icons.today_outlined),
            (
              'К синхронизации',
              '$pending',
              pending == 0 ? 'всё отправлено' : 'ожидают отправки',
              Icons.sync_outlined,
            ),
            ('Последняя', lastDate, 'дата записи', Icons.schedule_outlined),
          ];
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards
                .map(
                  (card) => SizedBox(
                    width: constraints.maxWidth >= 900
                        ? (constraints.maxWidth - 36) / 4
                        : constraints.maxWidth >= 560
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth,
                    child: _ModuleMetricCard(
                      title: card.$1,
                      value: card.$2,
                      detail: card.$3,
                      icon: card.$4,
                    ),
                  ),
                )
                .toList(),
          );
        },
      );
}

class _ModuleMetricCard extends StatelessWidget {
  const _ModuleMetricCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => _HoverPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _amber.withAlpha(18),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: _amberLine),
              ),
              child: Icon(icon, size: 18, color: _amber),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _primary,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _tertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.synced,
  });

  final String title;
  final String subtitle;
  final String detail;
  final bool synced;

  @override
  Widget build(BuildContext context) => _HoverPanel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              synced ? Icons.check_circle_outline : Icons.schedule,
              color: synced ? _green : _amber,
              size: 18,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _tertiary,
                      fontFamily: 'Cascadia Mono',
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (detail.isNotEmpty)
              Text(
                detail,
                style: TextStyle(
                  color: _amber,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 12,
                ),
              ),
          ],
        ),
      );
}

class _HoverPanel extends StatefulWidget {
  const _HoverPanel({
    required this.child,
    this.color,
    this.borderColor,
    this.padding = const EdgeInsets.all(18),
    this.glowOnHover = false,
    this.highlightOnHover = true,
  });

  final Widget child;
  final Color? color;
  final Color? borderColor;
  final EdgeInsets padding;
  final bool glowOnHover;
  final bool highlightOnHover;

  @override
  State<_HoverPanel> createState() => _HoverPanelState();
}

class _HoverPanelState extends State<_HoverPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered && widget.highlightOnHover
                ? Color.alphaBlend(
                    _amber.withAlpha(8), widget.color ?? _surface)
                : widget.color ?? _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered && widget.glowOnHover
                  ? _amberLine
                  : widget.borderColor ?? _line,
            ),
            boxShadow: _hovered && widget.glowOnHover
                ? const [BoxShadow(color: Color(0x18F0B429), blurRadius: 22)]
                : const [],
          ),
          child: widget.child,
        ),
      );
}

class _ConsoleBackground extends StatefulWidget {
  const _ConsoleBackground({
    required this.child,
    required this.isLight,
    this.animateDarkMesh = false,
  });

  final Widget child;
  final bool isLight;
  final bool animateDarkMesh;

  @override
  State<_ConsoleBackground> createState() => _ConsoleBackgroundState();
}

class _ConsoleBackgroundState extends State<_ConsoleBackground>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Offset?> _pointer = ValueNotifier<Offset?>(null);
  final List<_SiteMeshNode> _nodes = [];
  final _SiteMeshMouse _meshMouse = _SiteMeshMouse();
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    if (widget.isLight || widget.animateDarkMesh) _animation.repeat();
  }

  @override
  void didUpdateWidget(covariant _ConsoleBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasAnimated = oldWidget.isLight || oldWidget.animateDarkMesh;
    final isAnimated = widget.isLight || widget.animateDarkMesh;
    if (wasAnimated == isAnimated) return;
    if (isAnimated) {
      _animation.repeat();
    } else {
      _animation.stop();
      _pointer.value = null;
      _meshMouse.target = const Offset(-9999, -9999);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The dark product surface is deliberately plain black. Apart from
    // matching the requested visual direction, this prevents a full-screen
    // CustomPaint from consuming a frame while the user drags a dock.
    if (!widget.isLight && !widget.animateDarkMesh) {
      return ColoredBox(color: Colors.black, child: widget.child);
    }
    return MouseRegion(
      onHover: (event) {
        _meshMouse.target = event.localPosition;
        _pointer.value = event.localPosition;
      },
      onExit: (_) {
        _meshMouse.target = const Offset(-9999, -9999);
        _pointer.value = null;
      },
      child: ValueListenableBuilder<Offset?>(
        valueListenable: _pointer,
        builder: (context, pointer, child) => RepaintBoundary(
          child: CustomPaint(
            isComplex: true,
            willChange: true,
            painter: _ConsoleBackgroundPainter(
              pointer: pointer,
              animation: _animation,
              nodes: _nodes,
              meshMouse: _meshMouse,
              isLight: widget.isLight,
              phase: 0,
              pulses: const [],
              now: 0,
            ),
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _SiteMeshMouse {
  Offset current = const Offset(-9999, -9999);
  Offset target = const Offset(-9999, -9999);
}

class _SiteMeshNode {
  _SiteMeshNode({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.r,
    required this.depth,
    required this.phase,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double r;
  final double depth;
  final double phase;
}

class _GridPulse {
  const _GridPulse({required this.position, required this.createdAt});

  final Offset position;
  final double createdAt;
}

class _ConsoleBackgroundPainter extends CustomPainter {
  _ConsoleBackgroundPainter({
    this.pointer,
    required this.animation,
    required this.nodes,
    required this.meshMouse,
    required this.isLight,
    required this.phase,
    required this.pulses,
    required this.now,
  }) : super(repaint: animation);

  final Offset? pointer;
  final AnimationController animation;
  final List<_SiteMeshNode> nodes;
  final _SiteMeshMouse meshMouse;
  final bool isLight;
  final double phase;
  final List<_GridPulse> pulses;
  final double now;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCodevMesh(canvas, size);
    return;
    // Legacy console layers are intentionally kept below as a fallback
    // reference while the Codev_Tim mesh is the active renderer.
    /*
    final cursor = pointer ?? Offset(size.width * 0.78, size.height * 0.08);
    final normalizedX = (cursor.dx / size.width).clamp(0.0, 1.0);
    final normalizedY = (cursor.dy / size.height).clamp(0.0, 1.0);
    final gridOffset = Offset(
      (normalizedX - 0.5) * 8,
      (normalizedY - 0.5) * 6,
    );
    final gridPaint = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = 1;
    const spacing = 36.0;
    for (var x = -spacing; x < size.width + spacing; x += spacing) {
      canvas.drawLine(
        Offset(x + gridOffset.dx, 0),
        Offset(x + gridOffset.dx, size.height),
        gridPaint,
      );
    }
    for (var y = -spacing; y < size.height + spacing; y += spacing) {
      canvas.drawLine(
        Offset(0, y + gridOffset.dy),
        Offset(size.width, y + gridOffset.dy),
        gridPaint,
      );
    }
    _paintBreathingCells(canvas, size, gridOffset);
    _paintScanner(canvas, size);
    _paintMovingNodes(canvas, size);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: pointer == null
            ? const [Color(0x18F0B429), Colors.transparent]
            : const [Color(0x25F0B429), Color(0x08F0B429), Colors.transparent],
      ).createShader(
        Rect.fromCircle(center: cursor, radius: pointer == null ? 330 : 290),
      );
    canvas.drawCircle(cursor, pointer == null ? 330 : 290, glowPaint);

    if (pointer != null) {
      _paintPointerCell(canvas, cursor, gridOffset);
      final crosshairPaint = Paint()
        ..color = const Color(0x14F0B429)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(cursor.dx, cursor.dy - 15),
        Offset(cursor.dx, cursor.dy + 15),
        crosshairPaint,
      );
      canvas.drawLine(
        Offset(cursor.dx - 15, cursor.dy),
        Offset(cursor.dx + 15, cursor.dy),
        crosshairPaint,
      );
    }
    _paintPulses(canvas, gridOffset);
    */
  }

  void _paintCodevMesh(Canvas canvas, Size size) {
    final area = size.width * size.height;
    final baseCount = min(76, max(42, (area / 22000).round()));
    final count = max(28, (baseCount * (isLight ? 0.7 : 1)).round());
    if (nodes.length != count) {
      nodes
        ..clear()
        ..addAll(_createMeshNodes(count, size));
    }

    final elapsed = animation.lastElapsedDuration?.inMicroseconds ?? 0;
    final t = elapsed / 1000000 * 60 * 0.008;
    meshMouse.current = Offset(
      meshMouse.current.dx + (meshMouse.target.dx - meshMouse.current.dx) * 0.1,
      meshMouse.current.dy + (meshMouse.target.dy - meshMouse.current.dy) * 0.1,
    );
    final mouse = meshMouse.current;
    const connDist = 160.0;
    const connDistSq = connDist * connDist;
    const mouseDist = 220.0;
    const mouseDistSq = mouseDist * mouseDist;
    const mouseRepulse = 0.013;
    const mouseAttractNear = 0.004;
    const maxSpeed = 1.1;
    const speedDamp = 0.998;
    final hasMouse = mouse.dx > -9000;
    // The animated mesh follows the warm Codev visual language, while chat
    // bubbles keep the messages legible above it.
    final nodeColor = _amber;
    final lineColor = _amber;
    final nodeAlpha = isLight ? 0.92 : 1.0;
    final lineAlpha = isLight ? 0.85 : 1.0;

    // Paint the base explicitly so the animated background follows the active
    // palette and never falls back to the old dark canvas.
    canvas.drawColor(_base, BlendMode.src);
    for (final node in nodes) {
      node.vx += sin(t + node.phase) * 0.002;
      node.vy += cos(t * 0.7 + node.phase * 1.3) * 0.002;
      if (hasMouse) {
        final dx = node.x - mouse.dx;
        final dy = node.y - mouse.dy;
        final dsq = dx * dx + dy * dy;
        if (dsq < mouseDistSq) {
          final distance = sqrt(max(dsq, 0.0001));
          final force = 1 - distance / mouseDist;
          final factor = distance < mouseDist * 0.5
              ? -mouseRepulse * force
              : mouseAttractNear * force * 0.3;
          node.vx += (dx / distance) * factor;
          node.vy += (dy / distance) * factor;
        }
      }
      node.vx *= speedDamp;
      node.vy *= speedDamp;
      final speed = sqrt(node.vx * node.vx + node.vy * node.vy);
      final allowed = maxSpeed * node.depth;
      if (speed > allowed) {
        node.vx = node.vx / speed * allowed;
        node.vy = node.vy / speed * allowed;
      }
      node.x += node.vx;
      node.y += node.vy;
      if (node.x < 0) {
        node.vx = node.vx.abs();
        node.x = 0;
      }
      if (node.x > size.width) {
        node.vx = -node.vx.abs();
        node.x = size.width;
      }
      if (node.y < 0) {
        node.vy = node.vy.abs();
        node.y = 0;
      }
      if (node.y > size.height) {
        node.vy = -node.vy.abs();
        node.y = size.height;
      }
    }

    final grid = <int, List<int>>{};
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final key = _meshCellKey(
          (node.x / connDist).floor(), (node.y / connDist).floor());
      (grid[key] ??= <int>[]).add(i);
    }
    final linePaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < nodes.length; i++) {
      final a = nodes[i];
      final col = (a.x / connDist).floor();
      final row = (a.y / connDist).floor();
      for (var dc = -1; dc <= 1; dc++) {
        for (var dr = -1; dr <= 1; dr++) {
          final bucket = grid[_meshCellKey(col + dc, row + dr)];
          if (bucket == null) continue;
          for (final j in bucket) {
            if (j <= i) continue;
            final b = nodes[j];
            final dx = a.x - b.x;
            final dy = a.y - b.y;
            final distanceSq = dx * dx + dy * dy;
            if (distanceSq >= connDistSq) continue;
            final distance = sqrt(distanceSq);
            final strength = 1 - distance / connDist;
            final depth = (a.depth + b.depth) * 0.5;
            final clarity =
                _meshCenterClarity((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, size);
            var boost = 1.0;
            if (hasMouse) {
              final mx = (a.x + b.x) * 0.5 - mouse.dx;
              final my = (a.y + b.y) * 0.5 - mouse.dy;
              final mouseDistance = sqrt(mx * mx + my * my);
              if (mouseDistance < mouseDist)
                boost = 1 + (1 - mouseDistance / mouseDist) * 2.5;
            }
            final alpha =
                (strength * 0.22 * depth * boost * lineAlpha * clarity * 255)
                    .clamp(0, 255)
                    .round();
            linePaint
              ..color = lineColor.withAlpha(alpha)
              ..strokeWidth = (isLight ? 0.4 : 0.5) +
                  strength *
                      depth *
                      (isLight ? 0.55 : 0.8) *
                      (boost > 1 ? 1.2 : 1);
            canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), linePaint);
          }
        }
      }
    }

    for (final node in nodes) {
      final clarity = _meshCenterClarity(node.x, node.y, size);
      if (hasMouse) {
        final dx = node.x - mouse.dx;
        final dy = node.y - mouse.dy;
        final distance = sqrt(dx * dx + dy * dy);
        if (distance < mouseDist * 0.632) {
          final intensity = max(0, 1 - distance / (mouseDist * 0.632));
          final haloRadius = max(0.1, node.r * 4 * intensity);
          final halo = Paint()
            ..shader = RadialGradient(colors: [
              nodeColor.withAlpha(
                  (76 * intensity * node.depth * nodeAlpha * clarity).round()),
              Colors.transparent
            ]).createShader(Rect.fromCircle(
                center: Offset(node.x, node.y), radius: haloRadius));
          canvas.drawCircle(Offset(node.x, node.y), haloRadius, halo);
        }
      }
      final pulse = 0.85 + sin(t * 1.8 + node.phase) * 0.15;
      final radius = node.r * pulse;
      final alpha =
          ((0.35 + node.depth * 0.45) * pulse * nodeAlpha * clarity * 255)
              .clamp(0, 255)
              .round();
      canvas.drawCircle(Offset(node.x, node.y), radius,
          Paint()..color = nodeColor.withAlpha(alpha));
    }

    if (hasMouse) {
      final glow = Paint()
        ..shader = RadialGradient(colors: [
          lineColor.withAlpha(isLight ? 18 : 23),
          lineColor.withAlpha(isLight ? 8 : 9),
          Colors.transparent
        ], stops: const [
          0,
          0.38,
          0.7
        ]).createShader(Rect.fromCircle(center: mouse, radius: 300));
      canvas.drawCircle(mouse, 300, glow);
    }
    final vignette = Paint()
      ..shader = RadialGradient(
          colors: isLight
              ? [Colors.transparent, const Color(0x1212151C)]
              : [Colors.transparent, const Color(0x8C000000)],
          stops: const [0.4, 1]).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  final Random _meshRandom = Random();

  List<_SiteMeshNode> _createMeshNodes(int count, Size size) {
    final seeds = isLight
        ? List.generate(
            4,
            (_) => Offset(size.width * (0.12 + _meshRandom.nextDouble() * 0.76),
                size.height * (0.1 + _meshRandom.nextDouble() * 0.8)))
        : const <Offset>[];
    return List.generate(count, (index) {
      final depth = 0.3 + _meshRandom.nextDouble() * 0.7;
      var x = _meshRandom.nextDouble() * size.width;
      var y = _meshRandom.nextDouble() * size.height;
      if (isLight && _meshRandom.nextDouble() < 0.62) {
        final seed = seeds[index % seeds.length];
        final spread = min(size.width, size.height) * 0.16;
        x = (seed.dx + (_meshRandom.nextDouble() - 0.5) * spread)
            .clamp(0, size.width)
            .toDouble();
        y = (seed.dy + (_meshRandom.nextDouble() - 0.5) * spread)
            .clamp(0, size.height)
            .toDouble();
      }
      return _SiteMeshNode(
          x: x,
          y: y,
          vx: (_meshRandom.nextDouble() - 0.5) * 0.28 * depth,
          vy: (_meshRandom.nextDouble() - 0.5) * 0.28 * depth,
          r: isLight ? 0.85 + depth * 1.85 : 0.6 + depth * 1.6,
          depth: depth,
          phase: _meshRandom.nextDouble() * pi * 2);
    });
  }

  int _meshCellKey(int col, int row) => col * 100000 + row;

  double _meshCenterClarity(double x, double y, Size size) {
    if (!isLight) return 1;
    final dx = (x - size.width * 0.5) / (size.width * 0.28);
    final dy = (y - size.height * 0.38) / (size.height * 0.34);
    return min(1, 0.28 + sqrt(dx * dx + dy * dy) * 0.72);
  }

  void _paintBreathingCells(Canvas canvas, Size size, Offset gridOffset) {
    const spacing = 36.0;
    final cellPaint = Paint();
    final firstColumn = ((-gridOffset.dx) / spacing).floor() - 1;
    final firstRow = ((-gridOffset.dy) / spacing).floor() - 1;
    final columnCount = (size.width / spacing).ceil() + 2;
    final rowCount = (size.height / spacing).ceil() + 2;

    for (var column = firstColumn;
        column < firstColumn + columnCount;
        column++) {
      for (var row = firstRow; row < firstRow + rowCount; row++) {
        if ((column * 7 + row * 11).abs() % 13 > 2) continue;
        final breath =
            (sin(phase * pi * 2 + column * 0.42 + row * 0.67) + 1) / 2;
        final alpha = (3 + breath * 8).round();
        cellPaint.color = _amber.withAlpha(alpha);
        canvas.drawRect(
          Rect.fromLTWH(
            column * spacing + gridOffset.dx + 1,
            row * spacing + gridOffset.dy + 1,
            spacing - 2,
            spacing - 2,
          ),
          cellPaint,
        );
      }
    }
  }

  void _paintScanner(Canvas canvas, Size size) {
    final x = (phase * size.width * 1.6) - size.width * 0.25;
    final band = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Color(0x04F0B429),
          Color(0x12F0B429),
          Color(0x04F0B429),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(x - 80, 0, 160, size.height));
    canvas.drawRect(Rect.fromLTWH(x - 80, 0, 160, size.height), band);

    final linePaint = Paint()
      ..color = const Color(0x22F0B429)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
  }

  void _paintMovingNodes(Canvas canvas, Size size) {
    final nodePaint = Paint()..color = const Color(0x45F0B429);
    for (var index = 0; index < 9; index++) {
      final seed = index * 1.37;
      final x = ((phase * (0.12 + index * 0.013) + seed) % 1) * size.width;
      final y = (0.16 + (sin(phase * pi * 2 + seed) + 1) * 0.34) * size.height;
      final radius = 1.2 + (sin(phase * pi * 2 + seed * 2) + 1) * 0.7;
      canvas.drawCircle(Offset(x, y), radius, nodePaint);
    }
  }

  void _paintPointerCell(Canvas canvas, Offset cursor, Offset gridOffset) {
    const spacing = 36.0;
    final column = ((cursor.dx - gridOffset.dx) / spacing).floor();
    final row = ((cursor.dy - gridOffset.dy) / spacing).floor();
    final cellPaint = Paint()
      ..color = const Color(0x18F0B429)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0x55F0B429)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Rect.fromLTWH(
      column * spacing + gridOffset.dx + 1,
      row * spacing + gridOffset.dy + 1,
      spacing - 2,
      spacing - 2,
    );
    canvas.drawRect(rect, cellPaint);
    canvas.drawRect(rect, borderPaint);
  }

  void _paintPulses(Canvas canvas, Offset gridOffset) {
    const spacing = 36.0;
    for (final pulse in pulses) {
      final age = now - pulse.createdAt;
      if (age < 0 || age > 1.5) continue;
      final progress = age / 1.5;
      final radius = 6 + progress * 34;
      final pulsePaint = Paint()
        ..color = _amber.withAlpha((50 * (1 - progress)).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(pulse.position, radius, pulsePaint);
      final column = ((pulse.position.dx - gridOffset.dx) / spacing).floor();
      final row = ((pulse.position.dy - gridOffset.dy) / spacing).floor();
      final cellPaint = Paint()
        ..color = _amber.withAlpha((18 * (1 - progress)).round());
      canvas.drawRect(
        Rect.fromLTWH(
          column * spacing + gridOffset.dx + 1,
          row * spacing + gridOffset.dy + 1,
          spacing - 2,
          spacing - 2,
        ),
        cellPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConsoleBackgroundPainter oldDelegate) => true;
}

class _TelegramAssistantChat extends StatelessWidget {
  const _TelegramAssistantChat({
    required this.controller,
    required this.messages,
    required this.attachments,
    required this.draft,
    required this.busy,
    required this.listening,
    required this.error,
    required this.memoryCandidateId,
    required this.selectedModel,
    required this.onModelChanged,
    required this.models,
    required this.onSend,
    required this.onPickImages,
    required this.onRemoveAttachment,
    required this.onListen,
    required this.onSave,
    required this.onEdit,
    required this.onCancel,
    required this.onMemoryDecision,
    required this.sportProposal,
    required this.onSportPlanDecision,
    required this.composerFocus,
    required this.sectionLabel,
    required this.onDragUpdate,
    required this.onMinimize,
    required this.onClose,
    this.todaySummary,
    this.todayTotal,
    this.showTodayRail = false,
    this.fillHeight = false,
  });

  final TextEditingController controller;
  final List<Map<String, dynamic>> messages;
  final List<PlatformFile> attachments;
  final CaptureDraft? draft;
  final bool busy;
  final bool listening;
  final String? error;
  final String? memoryCandidateId;
  final String selectedModel;
  final ValueChanged<String> onModelChanged;
  final List<Map<String, String>> models;
  final VoidCallback onSend;
  final VoidCallback onPickImages;
  final ValueChanged<PlatformFile> onRemoveAttachment;
  final VoidCallback onListen;
  final VoidCallback onSave;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final ValueChanged<bool> onMemoryDecision;
  final _SportPlanProposal? sportProposal;
  final ValueChanged<bool> onSportPlanDecision;
  final FocusNode composerFocus;
  final String sectionLabel;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final Map<String, int>? todaySummary;
  final int? todayTotal;
  final bool showTodayRail;
  final bool fillHeight;

  void _useExample(String value) => controller.text = value;

  void _appendToComposer(String value) {
    final selection = controller.selection;
    final text = controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    controller.value = controller.value.copyWith(
      text: text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
      composing: TextRange.empty,
    );
  }

  KeyEventResult _handleChatKey(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (!composerFocus.hasFocus) {
          _appendToComposer('\n');
          composerFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      onSend();
      return KeyEventResult.handled;
    }

    if (composerFocus.hasFocus ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final character = event.character;
    if (character == null || character.isEmpty) return KeyEventResult.ignored;
    _appendToComposer(character);
    composerFocus.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 620;
    const composerHeight = 52.0;
    final hasTodayRail = showTodayRail && todaySummary != null;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _handleChatKey(context, event),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: _ConsoleBackground(
          isLight: false,
          animateDarkMesh: false,
          child: _HoverPanel(
            color: Colors.transparent,
            borderColor: _amberLine,
            highlightOnHover: false,
            padding: EdgeInsets.all(narrow ? 14 : 20),
            child: ConstrainedBox(
              constraints: fillHeight
                  ? const BoxConstraints()
                  : BoxConstraints.tightFor(height: narrow ? 420 : 440),
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: onDragUpdate,
                    child: Row(children: [
                      Container(
                        width: narrow ? 34 : 40,
                        height: narrow ? 34 : 40,
                        decoration: BoxDecoration(
                          color: _amber.withAlpha(24),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(Icons.auto_awesome_outlined,
                            color: _amber, size: narrow ? 19 : 22),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('AI помощник',
                                style: TextStyle(
                                    color: _primary,
                                    fontSize: narrow ? 18 : 20,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('Сейчас открыт раздел «$sectionLabel»',
                                style:
                                    TextStyle(color: _secondary, fontSize: 11)),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Выбрать модель AI',
                        enabled: !busy,
                        initialValue: selectedModel,
                        onSelected: onModelChanged,
                        itemBuilder: (_) => models
                            .map((model) => PopupMenuItem<String>(
                                  value: model['id'],
                                  child: Row(
                                    children: [
                                      if (model['id'] == selectedModel) ...[
                                        Icon(Icons.check_rounded,
                                            size: 17, color: _amber),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(model['label'] ?? model['id']!),
                                    ],
                                  ),
                                ))
                            .toList(),
                        icon: Icon(Icons.tune_rounded, size: 20, color: _amber),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Свернуть помощника',
                        onPressed: onMinimize,
                        icon: const Icon(Icons.remove_rounded, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Закрыть помощника',
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: _line),
                  Expanded(
                    child: Row(children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            if (messages.isEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: _base.withAlpha(205),
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(color: _lineStrong),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: _amber.withAlpha(24),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.bolt_rounded,
                                          color: _amber, size: 21),
                                    ),
                                    const SizedBox(width: 11),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('С чего начнём?',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w700)),
                                          SizedBox(height: 4),
                                          Text(
                                            'Опишите задачу, добавьте фото или выберите быстрый сценарий ниже.',
                                            style: TextStyle(height: 1.35),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                ActionChip(
                                  backgroundColor: _base.withAlpha(200),
                                  side: BorderSide(color: _amberLine),
                                  labelStyle: TextStyle(
                                      color: _secondary, fontSize: 11),
                                  label:
                                      const Text('Потратил 20 000 сум на кофе'),
                                  onPressed: () => _useExample(
                                      'Потратил 20 000 сум на кофе'),
                                ),
                                ActionChip(
                                  backgroundColor: _base.withAlpha(200),
                                  side: BorderSide(color: _amberLine),
                                  labelStyle: TextStyle(
                                      color: _secondary, fontSize: 11),
                                  label: const Text('Бег 30 минут'),
                                  onPressed: () => _useExample('Бег 30 минут'),
                                ),
                                ActionChip(
                                  backgroundColor: _base.withAlpha(200),
                                  side: BorderSide(color: _amberLine),
                                  labelStyle: TextStyle(
                                      color: _secondary, fontSize: 11),
                                  label:
                                      const Text('Занимался языком 20 минут'),
                                  onPressed: () =>
                                      _useExample('Занимался языком 20 минут'),
                                ),
                              ]),
                            ] else ...[
                              ...messages.map((item) {
                                final fromUser = item['role'] == 'Вы';
                                final messageAttachments =
                                    (item['attachments'] as List?)
                                            ?.whereType<PlatformFile>()
                                            .toList(growable: false) ??
                                        const <PlatformFile>[];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Align(
                                    alignment: fromUser
                                        ? const Alignment(0.58, 0)
                                        : Alignment.centerLeft,
                                    child: Container(
                                      constraints:
                                          const BoxConstraints(maxWidth: 620),
                                      padding: const EdgeInsets.all(13),
                                      decoration: BoxDecoration(
                                        color: fromUser
                                            ? _amber.withAlpha(28)
                                            : _base.withAlpha(205),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                            color: fromUser
                                                ? _amberLine
                                                : _lineStrong),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(item['text'] as String,
                                              style: TextStyle(
                                                  color: _primary,
                                                  height: 1.42)),
                                          if (messageAttachments
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Wrap(
                                              spacing: 7,
                                              runSpacing: 7,
                                              children: messageAttachments
                                                  .map(
                                                    (file) => ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                      child: SizedBox(
                                                        width: 92,
                                                        height: 92,
                                                        child:
                                                            file.bytes == null
                                                                ? ColoredBox(
                                                                    color:
                                                                        _recessed,
                                                                    child: Icon(
                                                                        Icons
                                                                            .image_outlined,
                                                                        color:
                                                                            _secondary),
                                                                  )
                                                                : Image.memory(
                                                                    file.bytes!,
                                                                    fit: BoxFit
                                                                        .cover),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(growable: false),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                            if (memoryCandidateId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child:
                                    Wrap(spacing: 8, runSpacing: 6, children: [
                                  const Text('Сохранить в память AI?'),
                                  TextButton(
                                      onPressed: () => onMemoryDecision(false),
                                      child: const Text('Не сейчас')),
                                  FilledButton(
                                      onPressed: () => onMemoryDecision(true),
                                      child: const Text('Подтвердить')),
                                ]),
                              ),
                            if (draft != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _ReviewCard(
                                  draft: draft!,
                                  onSave: onSave,
                                  onEdit: onEdit,
                                  onCancel: onCancel,
                                ),
                              ),
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _NoticeBanner(message: error!),
                              ),
                          ],
                        ),
                      ),
                      if (hasTodayRail) ...[
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 214,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: _TodayChatRail(
                                summary: todaySummary!, total: todayTotal ?? 0),
                          ),
                        ),
                      ],
                    ]),
                  ),
                  if (sportProposal != null) ...[
                    const SizedBox(height: 8),
                    _SportPlanProposalCard(
                      proposal: sportProposal!,
                      onApply: () => onSportPlanDecision(true),
                      onCancel: () => onSportPlanDecision(false),
                    ),
                  ],
                  if (attachments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 66,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: attachments.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final file = attachments[index];
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 66,
                                  height: 66,
                                  color: _recessed,
                                  child: file.bytes == null
                                      ? Icon(Icons.image_outlined,
                                          color: _secondary)
                                      : Image.memory(file.bytes!,
                                          fit: BoxFit.cover),
                                ),
                              ),
                              Positioned(
                                right: -5,
                                top: -5,
                                child: Material(
                                  color: _base,
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    tooltip: 'Убрать фото',
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 15,
                                    color: _primary,
                                    onPressed: () => onRemoveAttachment(file),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Container(
                        height: composerHeight,
                        decoration: BoxDecoration(
                          color: _recessed,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _lineStrong),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 42,
                              child: IconButton(
                                tooltip: 'Прикрепить фото',
                                color: _amber,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                onPressed: busy ? null : onPickImages,
                                icon: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 21),
                              ),
                            ),
                            Container(width: 1, height: 22, color: _lineStrong),
                            Expanded(
                              child: TextField(
                                controller: controller,
                                focusNode: composerFocus,
                                minLines: 1,
                                maxLines: 1,
                                textAlignVertical: TextAlignVertical.center,
                                textInputAction: TextInputAction.newline,
                                onSubmitted: (_) => onSend(),
                                decoration: const InputDecoration(
                                  hintText: 'Напишите сообщение…',
                                  isDense: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 13),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 42,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 40, minHeight: 40),
                                tooltip: listening
                                    ? 'Остановить запись'
                                    : 'Сказать голосом',
                                onPressed: onListen,
                                icon: Icon(
                                  listening
                                      ? Icons.stop_circle_outlined
                                      : Icons.mic_none,
                                  color: listening ? _red : _amber,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: composerHeight,
                      width: 52,
                      child: Tooltip(
                        message: 'Отправить',
                        child: Material(
                          color: busy ? _surface : _amber,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: busy ? null : onSend,
                            borderRadius: BorderRadius.circular(16),
                            child: Center(
                              child: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Icon(Icons.send_rounded, color: _base),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimizedAssistantDock extends StatelessWidget {
  const _MinimizedAssistantDock({
    required this.sectionLabel,
    required this.onDragUpdate,
    required this.onExpand,
    required this.onClose,
  });

  final String sectionLabel;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => _HoverPanel(
        color: _surface,
        borderColor: _amberLine,
        highlightOnHover: false,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: onDragUpdate,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _amber.withAlpha(24),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(Icons.auto_awesome_rounded, color: _amber, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI помощник',
                        style: TextStyle(
                            color: _primary, fontWeight: FontWeight.w700)),
                    Text('Рядом · $sectionLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _secondary, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Развернуть',
                onPressed: onExpand,
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 19),
              ),
            ],
          ),
        ),
      );
}

class _AssistantChatPanel extends StatelessWidget {
  const _AssistantChatPanel({
    required this.controller,
    required this.messages,
    required this.draft,
    required this.busy,
    required this.listening,
    required this.error,
    required this.memoryCandidateId,
    required this.onSend,
    required this.onListen,
    required this.onSave,
    required this.onEdit,
    required this.onCancel,
    required this.onMemoryDecision,
  });

  final TextEditingController controller;
  final List<Map<String, String>> messages;
  final CaptureDraft? draft;
  final bool busy;
  final bool listening;
  final String? error;
  final String? memoryCandidateId;
  final VoidCallback onSend;
  final VoidCallback onListen;
  final VoidCallback onSave;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final ValueChanged<bool> onMemoryDecision;

  void _useExample(String value) {
    controller.text = value;
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 620;
    return _HoverPanel(
      color: Colors.transparent,
      borderColor: _amberLine,
      glowOnHover: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: narrow ? 36 : 44,
                height: narrow ? 36 : 44,
                decoration: BoxDecoration(
                  color: _amber.withAlpha(24),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.auto_awesome_outlined,
                    color: _amber, size: narrow ? 20 : 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI помощник',
                        style: TextStyle(
                            color: _primary,
                            fontSize: narrow ? 19 : 21,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      'Пишите как в обычный чат. Если это запись — сам предложу нужный раздел.',
                      style: TextStyle(color: _secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (messages.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _base.withAlpha(210),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _line),
              ),
              child: Text(
                'Могу помочь с планом, объяснением или вашими данными. Расход, звонок, тренировку или урок английского подготовлю к сохранению — но ничего не запишу без подтверждения.',
                style: TextStyle(color: _secondary, height: 1.45),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = messages[index];
                  final fromUser = item['role'] == 'Вы';
                  return Align(
                    alignment:
                        fromUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 720),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: fromUser
                            ? _amber.withAlpha(28)
                            : _base.withAlpha(210),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: fromUser ? _amberLine : _lineStrong),
                      ),
                      child: Text(item['text']!,
                          style: TextStyle(color: _primary, height: 1.42)),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          if (messages.isEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                  backgroundColor: _base.withAlpha(200),
                  side: BorderSide(color: _amberLine),
                  labelStyle: TextStyle(color: _secondary, fontSize: 12),
                  label: const Text('Потратил 20 000 сум на кофе'),
                  onPressed: () => _useExample('Потратил 20 000 сум на кофе')),
              ActionChip(
                  backgroundColor: _base.withAlpha(200),
                  side: BorderSide(color: _amberLine),
                  labelStyle: TextStyle(color: _secondary, fontSize: 12),
                  label: const Text('Бег 30 минут'),
                  onPressed: () => _useExample('Бег 30 минут')),
              ActionChip(
                  backgroundColor: _base.withAlpha(200),
                  side: BorderSide(color: _amberLine),
                  labelStyle: TextStyle(color: _secondary, fontSize: 12),
                  label: const Text('Английский 20 минут'),
                  onPressed: () => _useExample('Английский 20 минут')),
            ]),
          if (messages.isEmpty) const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textAlignVertical: TextAlignVertical.center,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: 'Напишите сообщение…',
              isDense: narrow,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 14, vertical: narrow ? 10 : 13),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 50, minHeight: 44),
              prefixIcon:
                  Icon(Icons.chat_bubble_outline_rounded, color: _amber),
              suffixIcon: IconButton(
                tooltip: listening ? 'Остановить запись' : 'Сказать голосом',
                onPressed: onListen,
                icon: Icon(
                  listening ? Icons.stop_circle_outlined : Icons.mic_none,
                  color: listening ? _red : _amber,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _amber,
                foregroundColor: _base,
              ),
              onPressed: busy ? null : onSend,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(busy ? 'Думаю…' : 'Отправить'),
            ),
          ),
          if (memoryCandidateId != null) ...[
            const SizedBox(height: 14),
            Row(children: [
              const Expanded(child: Text('Сохранить это в память AI?')),
              TextButton(
                  onPressed: () => onMemoryDecision(false),
                  child: const Text('Не сейчас')),
              FilledButton(
                  onPressed: () => onMemoryDecision(true),
                  child: const Text('Подтвердить')),
            ]),
          ],
          if (draft != null) ...[
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _ReviewCard(
                    draft: draft!,
                    onSave: onSave,
                    onEdit: onEdit,
                    onCancel: onCancel),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 14),
            _NoticeBanner(message: error!),
          ],
        ],
      ),
    );
  }
}

class _UnifiedHomeComposer extends StatelessWidget {
  const _UnifiedHomeComposer({
    required this.controller,
    required this.draft,
    required this.busy,
    required this.listening,
    required this.notice,
    required this.onCapture,
    required this.onChat,
    required this.onListen,
    required this.onSave,
    required this.onEdit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final CaptureDraft? draft;
  final bool busy;
  final bool listening;
  final String? notice;
  final VoidCallback onCapture;
  final VoidCallback onChat;
  final VoidCallback onListen;
  final VoidCallback onSave;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => _HoverPanel(
        borderColor: _amberLine,
        glowOnHover: true,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _amber,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: _base),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Один запрос — два понятных действия',
                        style: TextStyle(
                          color: _primary,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Запишите событие или спросите AI обычными словами.',
                        style: TextStyle(color: _secondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText:
                    'Например: «потратил 20 000 сум на кофе» или «как распределить тренировки на неделю?»',
                prefixIcon:
                    Icon(Icons.chat_bubble_outline_rounded, color: _amber),
                suffixIcon: IconButton(
                  tooltip: listening ? 'Остановить запись' : 'Сказать голосом',
                  onPressed: onListen,
                  icon: Icon(
                    listening ? Icons.stop_circle_outlined : Icons.mic_none,
                    color: listening ? _red : _amber,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onCapture,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(busy ? 'Проверяем…' : 'Сохранить как запись'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onChat,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Спросить AI'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Записи не сохраняются автоматически: сначала покажем, что именно будет добавлено. AI отвечает в отдельном диалоге и не обещает того, чего не может сделать.',
              style: TextStyle(color: _tertiary, fontSize: 11, height: 1.45),
            ),
            if (draft != null) ...[
              const SizedBox(height: 18),
              _ReviewCard(
                draft: draft!,
                onSave: onSave,
                onEdit: onEdit,
                onCancel: onCancel,
              ),
            ],
            if (notice != null) ...[
              const SizedBox(height: 14),
              _NoticeBanner(message: notice!),
            ],
          ],
        ),
      );
}

class _AssistantPromptPanel extends StatelessWidget {
  const _AssistantPromptPanel({
    required this.controller,
    required this.plan,
    required this.tasks,
    required this.busy,
    required this.notice,
    required this.onParse,
    required this.onEdit,
    required this.onCompleteTask,
  });

  final TextEditingController controller;
  final AssistantPlan? plan;
  final List<AssistantTask> tasks;
  final bool busy;
  final String? notice;
  final VoidCallback onParse;
  final VoidCallback onEdit;
  final ValueChanged<String> onCompleteTask;

  @override
  Widget build(BuildContext context) => _HoverPanel(
        borderColor: _amberLine,
        glowOnHover: true,
        padding: const EdgeInsets.all(22),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 680;
            final input = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _amber,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(Icons.auto_awesome, color: _base),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Чем помочь сегодня?',
                        style: TextStyle(
                          color: _primary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    _ThemeStatusChip(),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Напишите запрос обычными словами. Ассистент разберёт фильм, фото, задачу или контакт и сразу выполнит понятное действие.',
                  style:
                      TextStyle(color: _secondary, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  onSubmitted: (_) => onParse(),
                  decoration: InputDecoration(
                    hintText: 'Например: подбери 5 комедий на вечер',
                    prefixIcon: Icon(Icons.chat_bubble_outline, color: _amber),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : onParse,
                        icon: busy
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _tertiary,
                                ),
                              )
                            : Icon(Icons.auto_awesome, size: 17),
                        label: Text(busy ? 'РАЗБИРАЮ…' : 'РАЗОБРАТЬ ЗАПРОС'),
                      ),
                    ),
                  ],
                ),
                if (plan != null) ...[
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.06),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey('${plan!.intent}:${plan!.originalText}'),
                      child: _AssistantPlanCard(
                        plan: plan!,
                        busy: busy,
                        onEdit: onEdit,
                      ),
                    ),
                  ),
                ],
                if (notice != null) ...[
                  const SizedBox(height: 12),
                  _NoticeBanner(message: notice!),
                ],
                if (tasks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _AssistantTaskList(
                    tasks: tasks,
                    onComplete: onCompleteTask,
                  ),
                ],
              ],
            );
            final capabilities = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'РАБОЧИЕ СЦЕНАРИИ',
                  style: TextStyle(
                    color: _tertiary,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 9,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: 12),
                _AssistantCapability(
                    Icons.movie_outlined, 'Подборки по количеству и жанру'),
                SizedBox(height: 9),
                _AssistantCapability(
                    Icons.image_outlined, 'Фото и изображения по запросу'),
                SizedBox(height: 9),
                _AssistantCapability(
                    Icons.calendar_today_outlined, 'Задачи + шаблон календаря'),
                SizedBox(height: 9),
                _AssistantCapability(Icons.phone_in_talk_outlined,
                    'Звонок через системное приложение'),
                SizedBox(height: 9),
                _AssistantCapability(
                    Icons.send_outlined, 'Telegram с готовым текстом'),
                SizedBox(height: 14),
                Text(
                  'КОНТАКТЫ ПО ИМЕНИ',
                  style: TextStyle(
                    color: _amber,
                    fontFamily: 'Cascadia Mono',
                    fontSize: 9,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Запомните номер один раз — дальше можно говорить «позвони мама».',
                  style:
                      TextStyle(color: _secondary, fontSize: 11, height: 1.4),
                ),
              ],
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: input),
                      const SizedBox(width: 24),
                      Expanded(flex: 3, child: capabilities),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [input, const SizedBox(height: 18), capabilities],
                  );
          },
        ),
      );
}

class _AssistantPlanCard extends StatelessWidget {
  const _AssistantPlanCard({
    required this.plan,
    required this.busy,
    required this.onEdit,
  });

  final AssistantPlan plan;
  final bool busy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isMovies = plan.intent == AssistantIntent.movies;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _amber.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _amberLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isMovies
                    ? Icons.movie_outlined
                    : plan.intent == AssistantIntent.visual
                        ? Icons.image_outlined
                        : plan.intent == AssistantIntent.task
                            ? Icons.calendar_today_outlined
                            : plan.intent == AssistantIntent.call
                                ? Icons.phone_in_talk_outlined
                                : plan.intent == AssistantIntent.contact
                                    ? Icons.contacts_outlined
                                    : Icons.send_outlined,
                color: _amber,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.title,
                  style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              TextButton(
                  onPressed: busy ? null : onEdit, child: Text('ИЗМЕНИТЬ')),
            ],
          ),
          const SizedBox(height: 10),
          if (isMovies)
            ...plan.movies.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 23,
                          child: Text(
                            '${entry.key + 1}'.padLeft(2, '0'),
                            style: TextStyle(
                                color: _amber,
                                fontFamily: 'Cascadia Mono',
                                fontSize: 11),
                          ),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: entry.value.imageUrl == null
                              ? SizedBox(
                                  width: 48,
                                  height: 68,
                                  child: _MissingImageBox(),
                                )
                              : Image.network(
                                  entry.value.imageUrl!,
                                  width: 48,
                                  height: 68,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox(
                                    width: 48,
                                    height: 68,
                                    child: _MissingImageBox(),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text:
                                      '${entry.value.title} (${entry.value.year})\n',
                                  style: TextStyle(
                                      color: _primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12),
                                ),
                                TextSpan(
                                  text:
                                      '${entry.value.genre} · ${entry.value.description}',
                                  style: TextStyle(
                                      color: _secondary,
                                      fontSize: 11,
                                      height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
          else if (plan.intent == AssistantIntent.visual) ...[
            if (plan.visualImageUrl != null)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.network(
                    plan.visualImageUrl!,
                    height: 230,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _MissingImageBox(),
                  ),
                ),
              ),
            if (plan.visualTitle != null) ...[
              const SizedBox(height: 12),
              Text(
                plan.visualTitle!,
                style: TextStyle(
                    color: _primary, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ],
            if (plan.visualDescription != null) ...[
              const SizedBox(height: 6),
              Text(
                plan.visualDescription!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _secondary, fontSize: 12, height: 1.4),
              ),
            ],
          ] else ...[
            Text(
              _planDescription(plan),
              style: TextStyle(color: _primary, fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  String _planDescription(AssistantPlan value) => switch (value.intent) {
        AssistantIntent.task =>
          '${value.taskTitle ?? 'Новая задача'}${value.dueAt == null ? '' : ' · ${_assistantDate(value.dueAt!)}'}',
        AssistantIntent.call =>
          '${value.contactName ?? 'Контакт без имени'}${value.phone == null ? '\nДобавьте номер телефона в запрос.' : ' · ${value.phone}'}',
        AssistantIntent.telegram =>
          '${value.contactName ?? value.telegramUsername ?? 'Контакт без адресата'}\n${value.message ?? ''}',
        AssistantIntent.movies => '',
        AssistantIntent.visual => value.visualQuery ?? 'животное',
        AssistantIntent.contact =>
          '${value.contactName ?? 'Контакт без имени'}${value.phone == null ? '' : ' · ${value.phone}'}${value.telegramUsername == null ? '' : ' · @${value.telegramUsername}'}',
      };
}

class _MissingImageBox extends StatelessWidget {
  const _MissingImageBox();

  @override
  Widget build(BuildContext context) => Container(
        height: 180,
        width: double.infinity,
        color: _elevated,
        alignment: Alignment.center,
        child: Icon(Icons.image_not_supported_outlined,
            color: _tertiary, size: 32),
      );
}

class _AssistantTaskList extends StatelessWidget {
  const _AssistantTaskList({required this.tasks, required this.onComplete});

  final List<AssistantTask> tasks;
  final ValueChanged<String> onComplete;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'БЛИЖАЙШИЕ ЗАДАЧИ',
            style: TextStyle(
                color: _tertiary,
                fontFamily: 'Cascadia Mono',
                fontSize: 9,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          ...tasks.take(4).map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        task.status == 'completed'
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: task.status == 'completed' ? _green : _amber,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${task.title}${task.dueAt == null ? '' : ' · ${_assistantDate(task.dueAt!)}'}',
                          style: TextStyle(
                            color: task.status == 'completed'
                                ? _tertiary
                                : _primary,
                            fontSize: 11,
                            decoration: task.status == 'completed'
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (task.status != 'completed')
                        IconButton(
                          tooltip: 'Завершить',
                          onPressed: () => onComplete(task.id),
                          icon: Icon(Icons.done, size: 16, color: _green),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              ),
        ],
      );
}

String _assistantDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

class _ThemeStatusChip extends StatelessWidget {
  const _ThemeStatusChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: _amber.withAlpha(22),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: _amberLine),
        ),
        child: Text(
          'ASSISTANT · ЛОКАЛЬНЫЙ ПАРСЕР',
          style: TextStyle(
            color: _amber,
            fontFamily: 'Cascadia Mono',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
}

class _AssistantCapability extends StatelessWidget {
  const _AssistantCapability(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 15, color: _amber),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: _primary, fontSize: 11)),
        ],
      );
}

class _PanelKicker extends StatelessWidget {
  const _PanelKicker({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 15, color: _amber),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: _amber,
              fontFamily: 'Cascadia Mono',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      );
}

class _AmberEyebrow extends StatelessWidget {
  _AmberEyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          color: _amber,
          fontFamily: 'Cascadia Mono',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.15,
        ),
      );
}

class _RailLabel extends StatelessWidget {
  const _RailLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          color: _tertiary,
          fontFamily: 'Cascadia Mono',
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _amber.withAlpha(18),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _amberLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulseDot(color: _green),
            SizedBox(width: 7),
            Text(
              'ГОТОВО',
              style: TextStyle(
                color: _green,
                fontFamily: 'Cascadia Mono',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
      );
}

class _TopBarStatus extends StatelessWidget {
  const _TopBarStatus();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: _green),
          SizedBox(width: 6),
          Text(
            'НА УСТРОЙСТВЕ',
            style: TextStyle(
              color: _tertiary,
              fontFamily: 'Cascadia Mono',
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      );
}

class _AiStatusIndicator extends StatefulWidget {
  const _AiStatusIndicator({required this.manager, required this.compact});

  final SessionManager manager;
  final bool compact;

  @override
  State<_AiStatusIndicator> createState() => _AiStatusIndicatorState();
}

class _AiStatusIndicatorState extends State<_AiStatusIndicator> {
  Map<String, dynamic>? status;
  String? error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await widget.manager.authenticatedRequest(
        'GET',
        '/api/ai/status',
      );
      if (mounted)
        setState(() {
          status = Map<String, dynamic>.from(result as Map);
          error = null;
        });
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.code);
    } catch (_) {
      if (mounted) setState(() => error = 'unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = status?['configured'] == true;
    final dot = error != null
        ? _red
        : status == null
            ? _amber
            : configured
                ? _green
                : _amber;
    final used = status?['usedToday'];
    final limit = status?['dailyLimit'];
    final credits = status?['availableBalance'];
    final label = error != null
        ? 'AI недоступен'
        : status == null
            ? 'AI проверка…'
            : configured
                ? (widget.compact
                    ? 'AI'
                    : 'AI API · $used/$limit · $credits кр.')
                : (widget.compact
                    ? 'AI'
                    : 'AI fallback · $used/$limit · $credits кр.');
    final tooltip = error != null
        ? 'AI API: ошибка $error'
        : status == null
            ? 'Проверяем AI API…'
            : '${configured ? 'OpenAI API подключён' : 'Работает локальный fallback'}\nМодель: ${status?['model']}\nДневной лимит: $used/$limit\nКредиты: $credits';
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: dot),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: configured ? _green : _tertiary,
              fontFamily: 'Cascadia Mono',
              fontSize: 9,
              letterSpacing: 0.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dotColor = color ?? _amber;
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: dotColor.withAlpha(100), blurRadius: 8)],
      ),
    );
  }
}

class _KeyboardHint extends StatelessWidget {
  const _KeyboardHint({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _elevated,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _line),
          ),
          child: Text(
            '↵ $label',
            style: TextStyle(
              color: _tertiary,
              fontFamily: 'Cascadia Mono',
              fontSize: 10,
            ),
          ),
        ),
      );
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final negative =
        message.contains('не удалось') || message.contains('Не удалось');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (negative ? _red : _green).withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (negative ? _red : _green).withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(
            negative ? Icons.error_outline : Icons.check_circle_outline,
            size: 17,
            color: negative ? _red : _green,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: negative ? _red : _green, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: _amber.withAlpha(18),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _amberLine),
        ),
        child: Text(
          type.toUpperCase(),
          style: TextStyle(
            color: _amber,
            fontFamily: 'Cascadia Mono',
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _ModuleIcon extends StatelessWidget {
  const _ModuleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: _amber.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _amberLine),
        ),
        child: Icon(icon, color: _amber, size: 26),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.name, required this.onCapture});

  final String name;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          final copy = Column(
            crossAxisAlignment:
                narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                'В разделе «$name» пока нет записей',
                textAlign: narrow ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  color: _primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Добавьте первую запись — здесь появится история и понятная сводка.',
                textAlign: narrow ? TextAlign.center : TextAlign.start,
                style: TextStyle(color: _secondary, fontSize: 12, height: 1.4),
              ),
            ],
          );
          final action = OutlinedButton.icon(
            onPressed: onCapture,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Добавить запись'),
          );
          return _HoverPanel(
            color: Colors.transparent,
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 16 : 22,
              vertical: 24,
            ),
            child: narrow
                ? Column(
                    children: [
                      Icon(Icons.inbox_outlined, color: _amber, size: 32),
                      const SizedBox(height: 12),
                      copy,
                      const SizedBox(height: 16),
                      SizedBox(width: double.infinity, child: action),
                    ],
                  )
                : Row(
                    children: [
                      Icon(Icons.inbox_outlined, color: _amber, size: 30),
                      const SizedBox(width: 16),
                      Expanded(child: copy),
                      const SizedBox(width: 16),
                      action,
                    ],
                  ),
          );
        },
      );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        color: _base,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _amber,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: _tertiary,
                  fontFamily: 'Cascadia Mono',
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        color: _base,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, style: TextStyle(color: _red)),
          ),
        ),
      );
}

class _WorkspaceModule {
  const _WorkspaceModule({
    required this.id,
    required this.shortLabel,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String id;
  final String shortLabel;
  final String label;
  final String description;
  final IconData icon;
}

class _WorkspaceSetupResult {
  const _WorkspaceSetupResult({
    required this.enabledModules,
    required this.languageProfile,
    required this.cashName,
    required this.cardName,
    required this.cashBalance,
    required this.cardBalance,
    required this.currency,
  });

  final Set<String> enabledModules;
  final Map<String, dynamic> languageProfile;
  final String cashName;
  final String cardName;
  final double cashBalance;
  final double cardBalance;
  final String currency;
}

class _WorkspaceSetupScreen extends StatefulWidget {
  const _WorkspaceSetupScreen({
    required this.database,
    required this.modules,
    required this.initialModules,
    required this.initialLanguageProfile,
    required this.onComplete,
    this.onCancel,
  });

  final LocalDatabase database;
  final List<_WorkspaceModule> modules;
  final Set<String> initialModules;
  final Map<String, dynamic> initialLanguageProfile;
  final Future<void> Function(_WorkspaceSetupResult result) onComplete;
  final VoidCallback? onCancel;

  @override
  State<_WorkspaceSetupScreen> createState() => _WorkspaceSetupScreenState();
}

class _WorkspaceSetupScreenState extends State<_WorkspaceSetupScreen> {
  late Set<String> selected;
  late String targetLanguage;
  late String languageGoal;
  late String currentLevel;
  late int weeks;
  String currency = 'UZS';
  int step = 0;
  bool busy = false;
  final otherLanguage = TextEditingController();
  late final TextEditingController cashName;
  late final TextEditingController cardName;
  late final TextEditingController cashBalance;
  late final TextEditingController cardBalance;

  static const languages = [
    'Английский',
    'Испанский',
    'Немецкий',
    'Французский',
    'Китайский',
    'Корейский',
    'Арабский',
    'Турецкий',
    'Русский',
    'Другой',
  ];

  @override
  void initState() {
    super.initState();
    selected = {...widget.initialModules};
    final savedLanguage =
        widget.initialLanguageProfile['targetLanguage'] as String? ??
            'Английский';
    targetLanguage =
        languages.contains(savedLanguage) ? savedLanguage : 'Другой';
    if (targetLanguage == 'Другой') otherLanguage.text = savedLanguage;
    languageGoal =
        widget.initialLanguageProfile['goal'] as String? ?? 'Свободно общаться';
    currentLevel = widget.initialLanguageProfile['currentLevel'] as String? ??
        'Начинаю с нуля';
    weeks = (widget.initialLanguageProfile['weeks'] as num?)?.toInt() ?? 12;
    final accounts = widget.database.moneyAccounts();
    MoneyAccount? find(String id) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    final cash = find('cash-main');
    final card = find('card-main');
    currency = cash?.currency ?? card?.currency ?? 'UZS';
    cashName = TextEditingController(text: cash?.name ?? 'Наличные');
    cardName = TextEditingController(text: card?.name ?? 'Основная карта');
    cashBalance = TextEditingController(
      text: cash == null || cash.initialBalance == 0
          ? ''
          : cash.initialBalance.toStringAsFixed(0),
    );
    cardBalance = TextEditingController(
      text: card == null || card.initialBalance == 0
          ? ''
          : card.initialBalance.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    otherLanguage.dispose();
    cashName.dispose();
    cardName.dispose();
    cashBalance.dispose();
    cardBalance.dispose();
    super.dispose();
  }

  List<String> get steps => [
        'modules',
        if (selected.contains('languages')) 'language',
        if (selected.contains('money')) 'money',
        'ready',
      ];

  String get actualLanguage =>
      targetLanguage == 'Другой' ? otherLanguage.text.trim() : targetLanguage;

  double _amount(TextEditingController controller) =>
      double.tryParse(
        controller.text.replaceAll(' ', '').replaceAll(',', '.'),
      ) ??
      0;

  bool get canContinue {
    final current = steps[step.clamp(0, steps.length - 1).toInt()];
    if (current == 'modules') return selected.isNotEmpty;
    if (current == 'language') return actualLanguage.length >= 2;
    if (current == 'money') {
      return cashName.text.trim().isNotEmpty && cardName.text.trim().isNotEmpty;
    }
    return true;
  }

  Future<void> _next() async {
    if (!canContinue || busy) return;
    if (step < steps.length - 1) {
      setState(() => step += 1);
      return;
    }
    setState(() => busy = true);
    try {
      await widget.onComplete(
        _WorkspaceSetupResult(
          enabledModules: {...selected},
          languageProfile: {
            ...widget.initialLanguageProfile,
            'targetLanguage': actualLanguage,
            'goal': languageGoal,
            'currentLevel': currentLevel,
            'weeks': weeks,
          },
          cashName: cashName.text.trim(),
          cardName: cardName.text.trim(),
          cashBalance: _amount(cashBalance),
          cardBalance: _amount(cardBalance),
          currency: currency,
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (step >= steps.length) step = steps.length - 1;
    final current = steps[step];
    return Scaffold(
      body: _ConsoleBackground(
        isLight: Theme.of(context).brightness == Brightness.light,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: _HoverPanel(
                  borderColor: _amberLine,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: _amber.withAlpha(24),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(Icons.dashboard_customize_rounded,
                                color: _amber),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Соберите своё пространство',
                                    style: TextStyle(
                                        color: _primary,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 3),
                                Text(
                                  'Оставьте только то, что действительно хотите вести. Главная и быстрые записи доступны всегда.',
                                  style:
                                      TextStyle(color: _secondary, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                          if (widget.onCancel != null)
                            IconButton(
                              tooltip: 'Закрыть',
                              onPressed: widget.onCancel,
                              icon: const Icon(Icons.close_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: List.generate(
                          steps.length,
                          (index) => Expanded(
                            child: Container(
                              height: 4,
                              margin: EdgeInsets.only(
                                  right: index == steps.length - 1 ? 0 : 7),
                              decoration: BoxDecoration(
                                color: index <= step ? _amber : _lineStrong,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (current == 'modules') _modulesStep(),
                      if (current == 'language') _languageStep(),
                      if (current == 'money') _moneyStep(),
                      if (current == 'ready') _readyStep(),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          if (step > 0)
                            TextButton.icon(
                              onPressed:
                                  busy ? null : () => setState(() => step -= 1),
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Назад'),
                            ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: canContinue && !busy ? _next : null,
                            icon: Icon(step == steps.length - 1
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded),
                            label: Text(busy
                                ? 'Сохраняем…'
                                : step == steps.length - 1
                                    ? 'Открыть моё пространство'
                                    : 'Продолжить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modulesStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Что должно помогать вам каждый день?',
              style: TextStyle(
                  color: _primary, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Можно выбрать один раздел, несколько или вернуться позже.',
              style: TextStyle(color: _secondary)),
          if (selected.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
                'Выберите хотя бы один раздел. Остальные можно добавить позже.',
                style: TextStyle(color: _amber, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 700
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: widget.modules.map((module) {
                final active = selected.contains(module.id);
                return SizedBox(
                  width: width,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() {
                      active
                          ? selected.remove(module.id)
                          : selected.add(module.id);
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: active ? _amber.withAlpha(20) : _surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: active ? _amber : _lineStrong,
                            width: active ? 1.4 : 1),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: active ? _amber.withAlpha(28) : _elevated,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(module.icon,
                                color: active ? _amber : _secondary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(module.label,
                                    style: TextStyle(
                                        color: _primary,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(module.description,
                                    style: TextStyle(
                                        color: _secondary,
                                        fontSize: 12,
                                        height: 1.35)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            active
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: active ? _amber : _tertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          }),
        ],
      );

  Widget _languageStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Какой язык хотите изучать?',
              style: TextStyle(
                  color: _primary, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              'Вы выбираете цель и темп. Первый план появится сразу, а затем его можно уточнять по вашему прогрессу.',
              style: TextStyle(color: _secondary, height: 1.4)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: targetLanguage,
            decoration: const InputDecoration(
                labelText: 'Язык', prefixIcon: Icon(Icons.translate_rounded)),
            items: languages
                .map((language) =>
                    DropdownMenuItem(value: language, child: Text(language)))
                .toList(),
            onChanged: (value) =>
                setState(() => targetLanguage = value ?? targetLanguage),
          ),
          if (targetLanguage == 'Другой') ...[
            const SizedBox(height: 10),
            TextField(
              controller: otherLanguage,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Напишите язык',
                  prefixIcon: Icon(Icons.edit_outlined)),
            ),
          ],
          const SizedBox(height: 14),
          Text('Главная цель',
              style: TextStyle(color: _primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Свободно общаться',
              'Работа и карьера',
              'Переезд',
              'Путешествия',
              'Экзамен',
            ]
                .map((goal) => ChoiceChip(
                      label: Text(goal),
                      selected: languageGoal == goal,
                      onSelected: (_) => setState(() => languageGoal = goal),
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: currentLevel,
                  decoration:
                      const InputDecoration(labelText: 'Текущий уровень'),
                  items: [
                    'Начинаю с нуля',
                    'Знаю основы',
                    'Могу немного говорить',
                    'Уверенно общаюсь',
                  ]
                      .map((level) =>
                          DropdownMenuItem(value: level, child: Text(level)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => currentLevel = value ?? currentLevel),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  initialValue: weeks,
                  decoration: const InputDecoration(labelText: 'Длительность'),
                  items: const [6, 12, 24, 36]
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text('$value недель')))
                      .toList(),
                  onChanged: (value) => setState(() => weeks = value ?? weeks),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _moneyStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Сколько денег у вас сейчас?',
              style: TextStyle(
                  color: _primary, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              'Это стартовая точка, а не доход. Дальше остатки будут меняться только после подтверждённых операций.',
              style: TextStyle(color: _secondary, height: 1.4)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: cashName,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Кошелёк',
                      prefixIcon: Icon(Icons.payments_outlined)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: cashBalance,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Остаток наличных'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: cardName,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Основная карта',
                      prefixIcon: Icon(Icons.credit_card_outlined)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: cardBalance,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Остаток карты'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'Основная валюта'),
              items: const [
                DropdownMenuItem(value: 'UZS', child: Text('UZS · сум')),
                DropdownMenuItem(value: 'USD', child: Text('USD · доллар')),
              ],
              onChanged: (value) =>
                  setState(() => currency = value ?? currency),
            ),
          ),
          const SizedBox(height: 10),
          Text(
              'Дополнительные карты, банковские счета и электронные кошельки можно добавить в разделе «Деньги».',
              style: TextStyle(color: _tertiary, fontSize: 12)),
        ],
      );

  Widget _readyStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Готово. Ничего лишнего.',
              style: TextStyle(
                  color: _primary, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              'Начните с одной фразы. Приложение подготовит запись и ничего не сохранит без вашего подтверждения.',
              style: TextStyle(color: _secondary, height: 1.4)),
          const SizedBox(height: 16),
          _HoverPanel(
            color: _elevated,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelKicker(icon: Icons.bolt_rounded, label: 'ПЕРВЫЙ ШАГ'),
                const SizedBox(height: 10),
                Text(
                    selected.contains('money')
                        ? 'Например: «Потратил 20 000 сум на кофе»'
                        : 'Откройте выбранный раздел и начните с первого шага',
                    style: TextStyle(
                        color: _primary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(
                    selected.contains('money')
                        ? 'Вы увидите готовую карточку расхода, проверите сумму и только потом сохраните.'
                        : 'На главной всегда можно сделать быструю запись, а раздел покажет следующий понятный шаг.',
                    style: TextStyle(color: _secondary, height: 1.4)),
              ],
            ),
          ),
          if (selected.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.modules
                  .where((module) => selected.contains(module.id))
                  .map((module) => Chip(
                        avatar: Icon(module.icon, size: 16),
                        label: Text(module.label),
                      ))
                  .toList(),
            ),
          ],
        ],
      );
}

class _Destination {
  const _Destination(this.id, this.shortLabel, this.label, this.icon);

  final String id;
  final String shortLabel;
  final String label;
  final IconData icon;
}

class _BetaWorkspacePanel extends StatelessWidget {
  const _BetaWorkspacePanel({required this.session, required this.manager});
  final BetaSession session;
  final SessionManager manager;

  @override
  Widget build(BuildContext context) {
    final active = session.activeTenant;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _lineStrong)),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.verified_user_outlined, color: _amber),
          Text(
              '${session.user.displayName} · ${active?.name ?? 'Пространство'}',
              style: TextStyle(color: _primary, fontWeight: FontWeight.w700)),
          if (session.tenants.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Сменить пространство',
              onSelected: (value) => manager.switchTenant(value),
              itemBuilder: (_) => session.tenants
                  .map((item) =>
                      PopupMenuItem(value: item.id, child: Text(item.name)))
                  .toList(),
              child: const Chip(label: Text('Сменить')),
            ),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _AiCaptureDialog(manager: manager)),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Умная запись')),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _AiChatDialog(manager: manager)),
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Помощник')),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _AiCreditsDialog(manager: manager)),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Статус умных функций')),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _KnowledgeDialog(manager: manager)),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Knowledge')),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _InvitationDialog(manager: manager)),
              icon: const Icon(Icons.vpn_key_outlined),
              label: const Text('Код приглашения')),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _OwnerInvitationsDialog(manager: manager)),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Пригласить')),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _FeedbackDialog(manager: manager)),
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('Feedback')),
          OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      _DiagnosticsDialog(manager: manager, session: session)),
              icon: const Icon(Icons.monitor_heart_outlined),
              label: const Text('Диагностика')),
          TextButton.icon(
              onPressed: () => manager.logout(),
              icon: const Icon(Icons.logout),
              label: const Text('Выйти')),
        ],
      ),
    );
  }
}

String _betaUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class _AiCaptureDialog extends StatefulWidget {
  const _AiCaptureDialog({required this.manager});
  final SessionManager manager;
  @override
  State<_AiCaptureDialog> createState() => _AiCaptureDialogState();
}

class _AiCaptureDialogState extends State<_AiCaptureDialog> {
  final text = TextEditingController();
  Map<String, dynamic>? preview;
  String? error;
  bool busy = false;
  String? confirmationId;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> createPreview() async {
    setState(() {
      busy = true;
      error = null;
      preview = null;
    });
    try {
      final response = await widget.manager.authenticatedRequest(
              'POST', '/api/ai/capture/preview', body: {'text': text.text})
          as Map<String, dynamic>;
      if (mounted) setState(() => preview = response);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> commit() async {
    final value = preview;
    if (value == null) return;
    setState(() {
      busy = true;
      error = null;
      confirmationId ??= _betaUuid();
    });
    try {
      final result = await widget.manager.authenticatedRequest(
          'POST', '/api/ai/capture/commit', body: {
        'previewId': value['id'],
        'confirmationId': confirmationId
      }) as Map<String, dynamic>;
      if (mounted) setState(() => preview = {...value, 'committed': result});
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('AI Quick Capture'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                TextField(
                    controller: text,
                    onChanged: (_) => setState(() {}),
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                        hintText:
                            'Например: Сегодня сделал жим лёжа 60 кг на 10, 8 и 7 повторений')),
                const SizedBox(height: 12),
                if (preview != null) _JsonPreview(value: preview!),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ])),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Закрыть')),
          if (preview == null)
            FilledButton(
                onPressed:
                    busy || text.text.trim().isEmpty ? null : createPreview,
                child: busy
                    ? const CircularProgressIndicator()
                    : const Text('Получить preview')),
          if (preview != null && preview!['committed'] == null)
            FilledButton(
                onPressed: busy ? null : commit,
                child: busy
                    ? const CircularProgressIndicator()
                    : const Text('Подтвердить сохранение')),
        ],
      );
}

class _AiChatDialog extends StatefulWidget {
  const _AiChatDialog({required this.manager, this.initialMessage});
  final SessionManager manager;
  final String? initialMessage;
  @override
  State<_AiChatDialog> createState() => _AiChatDialogState();
}

class _AiChatDialogState extends State<_AiChatDialog> {
  final controller = TextEditingController();
  final messages = <Map<String, String>>[];
  String? conversationId;
  String? candidateId;
  String? error;
  bool busy = false;
  String? creditStatus;

  @override
  void initState() {
    super.initState();
    messages.add({
      'role': 'AI',
      'text':
          'Я могу помочь с планом, объяснением или вопросом по вашим данным. Для траты, тренировки или занятия используйте «Сохранить как запись» на главной — там будет подтверждение.'
    });
    final initial = widget.initialMessage?.trim();
    if (initial != null && initial.isNotEmpty) {
      controller.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => send());
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final message = controller.text.trim();
    if (message.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      messages.add({'role': 'Вы', 'text': message});
      controller.clear();
    });
    try {
      final result = await widget.manager.authenticatedRequest(
          'POST', '/api/ai/chat', body: {
        'message': message,
        if (conversationId != null) 'conversationId': conversationId
      }) as Map<String, dynamic>;
      if (mounted)
        setState(() {
          conversationId = result['conversationId'] as String?;
          candidateId = result['memoryCandidateId'] as String?;
          messages.add({'role': 'AI', 'text': result['answer'] as String});
          creditStatus = result['creditsCharged'] == null
              ? null
              : 'Списано ${result['creditsCharged']} AI-кредитов · остаток ${result['creditBalance']}';
        });
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> decideMemory(bool approve) async {
    final id = candidateId;
    if (id == null) return;
    try {
      await widget.manager.authenticatedRequest('POST',
          '/api/ai/memory/candidates/$id/${approve ? 'approve' : 'reject'}');
      if (mounted) setState(() => candidateId = null);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: _amber, borderRadius: BorderRadius.circular(11)),
            child: Icon(Icons.auto_awesome_rounded, color: _base, size: 20),
          ),
          const SizedBox(width: 10),
          const Text('AI помощник'),
        ]),
        content: SizedBox(
            width: 640,
            height: 360,
            child: Column(children: [
              Expanded(
                  child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = messages[index];
                  final fromUser = item['role'] == 'Вы';
                  return Align(
                    alignment:
                        fromUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: fromUser ? _amber.withAlpha(26) : _recessed,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: fromUser ? _amberLine : _line),
                      ),
                      child: Text(item['text']!,
                          style: TextStyle(color: _primary, height: 1.42)),
                    ),
                  );
                },
              )),
              if (candidateId != null)
                Row(children: [
                  const Expanded(child: Text('Сохранить кандидата памяти?')),
                  TextButton(
                      onPressed: () => decideMemory(false),
                      child: const Text('Нет')),
                  FilledButton(
                      onPressed: () => decideMemory(true),
                      child: const Text('Подтвердить'))
                ]),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (creditStatus != null)
                Text(creditStatus!, style: TextStyle(color: _secondary)),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: controller,
                        onSubmitted: (_) => send(),
                        decoration: const InputDecoration(
                            hintText: 'Спросите о своих данных'))),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: busy ? null : send,
                    child: busy
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.send))
              ]),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'))
        ],
      );
}

class _KnowledgeDialog extends StatefulWidget {
  const _KnowledgeDialog({required this.manager});
  final SessionManager manager;
  @override
  State<_KnowledgeDialog> createState() => _KnowledgeDialogState();
}

class _KnowledgeDialogState extends State<_KnowledgeDialog> {
  final title = TextEditingController(text: 'Новая заметка');
  final path = TextEditingController(text: 'Notes/new-note.md');
  final content = TextEditingController();
  List<dynamic> documents = [];
  Map<String, dynamic>? importPreview;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    title.dispose();
    path.dispose();
    content.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final result = await widget.manager
          .authenticatedRequest('GET', '/api/knowledge/documents');
      if (mounted) setState(() => documents = result as List<dynamic>);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.manager
          .authenticatedRequest('POST', '/api/knowledge/documents', body: {
        'path': path.text,
        'title': title.text,
        'documentType': 'free-note',
        'content': content.text
      });
      await load();
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exportVault() async {
    try {
      final result = await widget.manager.authenticatedRequest(
          'GET', '/api/knowledge/export') as Map<String, dynamic>;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Vault export подготовлен: ${(result['documents'] as List).length} документов.')));
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    }
  }

  Future<void> importVault() async {
    setState(() {
      busy = true;
      error = null;
      importPreview = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      if (bytes == null) return;
      final preview =
          await widget.manager.uploadVaultDryRun(bytes) as Map<String, dynamic>;
      if (mounted) setState(() => importPreview = preview);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> commitImport() async {
    final preview = importPreview;
    if (preview == null) return;
    setState(() => busy = true);
    try {
      final files = (preview['files'] as List<dynamic>? ?? const []);
      final conflicts = <String, String>{
        for (final value in files)
          if (value is Map<String, dynamic> && value['action'] == 'conflict')
            value['path'] as String: 'import-as-conflict-copy',
      };
      await widget.manager.authenticatedRequest(
        'POST',
        '/api/knowledge/vault/import/commit',
        body: {
          'importSessionId': preview['importSessionId'],
          'archiveHash': preview['archiveHash'],
          'idempotencyKey': _betaUuid(),
          'conflicts': conflicts,
        },
      );
      if (mounted) {
        setState(() => importPreview = null);
        await load();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vault import completed.')));
      }
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Knowledge / Markdown'),
          content: SizedBox(
              width: 700,
              height: 520,
              child: Column(children: [
                Expanded(
                    child: ListView(
                        children: documents.map((item) {
                  final json = item as Map<String, dynamic>;
                  return ListTile(
                      title: Text(json['title'] as String),
                      subtitle: Text(json['path'] as String));
                }).toList())),
                const Divider(),
                TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Название')),
                TextField(
                    controller: path,
                    decoration: const InputDecoration(labelText: 'Путь .md')),
                TextField(
                    controller: content,
                    minLines: 4,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Markdown')),
                if (importPreview != null)
                  Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      child: Text(
                          'Import preview: ${importPreview!['newDocuments']} new, ${importPreview!['updatedDocuments']} updates, ${importPreview!['conflicts']} conflicts. Conflicts will be imported as separate copies; no server document is overwritten.')),
                if (error != null)
                  Text(error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
              ])),
          actions: [
            TextButton(
                onPressed: exportVault, child: const Text('Export vault')),
            TextButton(
                onPressed: busy ? null : importVault,
                child: const Text('Import ZIP')),
            if (importPreview != null)
              FilledButton(
                  onPressed: busy ? null : commitImport,
                  child: const Text('Confirm import')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть')),
            FilledButton(
                onPressed: busy ? null : save, child: const Text('Сохранить'))
          ]);
}

class _InvitationDialog extends StatefulWidget {
  const _InvitationDialog({required this.manager});
  final SessionManager manager;
  @override
  State<_InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<_InvitationDialog> {
  final code = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> accept() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.manager.acceptInvitation(code.text.trim());
      if (mounted) Navigator.pop(context);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Принять приглашение'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: code,
                decoration:
                    const InputDecoration(labelText: 'Код приглашения')),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: busy ? null : accept, child: const Text('Принять'))
          ]);
}

class _JsonPreview extends StatelessWidget {
  const _JsonPreview({required this.value});
  final Map<String, dynamic> value;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: _elevated, borderRadius: BorderRadius.circular(8)),
      child: SelectableText(const JsonEncoder.withIndent('  ').convert(value)));
}

class _DiagnosticsDialog extends StatefulWidget {
  const _DiagnosticsDialog({required this.manager, required this.session});
  final SessionManager manager;
  final BetaSession session;
  @override
  State<_DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<_DiagnosticsDialog> {
  String health = 'Проверяем…';
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(check());
  }

  Future<void> check() async {
    try {
      final result =
          await widget.manager.authenticatedRequest('GET', '/health');
      if (mounted)
        setState(() => health = result is Map ? '${result['status']}' : 'ok');
    } on ApiFailure catch (value) {
      if (mounted)
        setState(() {
          health = 'Недоступен';
          error = value.requestId;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Beta diagnostics'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Версия: 0.1.0+1'),
                Text('Среда: ${BetaConfig.environment}'),
                Text('API: ${BetaConfig.apiBaseUrl}'),
                Text('API health: $health'),
                Text('Auth: ${widget.session.user.email}'),
                Text(
                    'Tenant: ${widget.session.activeTenant?.name ?? 'не выбран'}'),
                const Text('AI: backend-controlled'),
                const Text('Knowledge: backend-controlled'),
                if (error != null) Text('Последний correlation ID: $error')
              ]),
          actions: [
            TextButton(onPressed: check, child: const Text('Обновить')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'))
          ]);
}

class _OwnerInvitationsDialog extends StatefulWidget {
  const _OwnerInvitationsDialog({required this.manager});
  final SessionManager manager;
  @override
  State<_OwnerInvitationsDialog> createState() =>
      _OwnerInvitationsDialogState();
}

class _OwnerInvitationsDialogState extends State<_OwnerInvitationsDialog> {
  final email = TextEditingController();
  List<dynamic> invitations = [];
  String? oneTimeCode;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final result = await widget.manager
          .authenticatedRequest('GET', '/api/beta/invitations');
      if (mounted) setState(() => invitations = result as List<dynamic>);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> create() async {
    setState(() {
      busy = true;
      error = null;
      oneTimeCode = null;
    });
    try {
      final result = await widget.manager.authenticatedRequest(
          'POST', '/api/beta/invitations', body: {
        'email': email.text,
        'role': 'MEMBER',
        'expiresInDays': 14
      }) as Map<String, dynamic>;
      if (mounted)
        setState(() {
          oneTimeCode = result['token'] as String?;
          email.clear();
        });
      await load();
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(String id) async {
    try {
      await widget.manager
          .authenticatedRequest('POST', '/api/beta/invitations/$id/revoke');
      await load();
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    }
  }

  Future<void> resend(String id) async {
    try {
      final result = await widget.manager.authenticatedRequest(
          'POST', '/api/beta/invitations/$id/resend') as Map<String, dynamic>;
      if (mounted) setState(() => oneTimeCode = result['token'] as String?);
      await load();
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Beta invitations'),
          content: SizedBox(
              width: 620,
              height: 420,
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: email,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText: 'Email тестировщика'))),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed:
                          busy || !email.text.contains('@') ? null : create,
                      child: const Text('Создать'))
                ]),
                if (oneTimeCode != null)
                  SelectableText('Передайте код один раз: $oneTimeCode'),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                const Divider(),
                Expanded(
                    child: ListView(
                        children: invitations.map((value) {
                  final item = value as Map<String, dynamic>;
                  final pending = item['status'] == 'PENDING';
                  return ListTile(
                      title: Text(item['email'] as String),
                      subtitle: Text(
                          '${item['status']} · ${item['deliveryStatus'] ?? 'PENDING'} · до ${item['expiresAt']}'),
                      trailing: pending
                          ? Wrap(children: [
                              TextButton(
                                  onPressed: () => resend(item['id'] as String),
                                  child: const Text('Resend')),
                              TextButton(
                                  onPressed: () => revoke(item['id'] as String),
                                  child: const Text('Отозвать')),
                            ])
                          : null);
                }).toList()))
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'))
          ]);
}

class _PrivacyDialog extends StatefulWidget {
  const _PrivacyDialog({
    required this.database,
    required this.enabledModules,
  });

  final LocalDatabase database;
  final Set<String> enabledModules;

  @override
  State<_PrivacyDialog> createState() => _PrivacyDialogState();
}

class _PrivacyDialogState extends State<_PrivacyDialog> {
  final contextAccess = <String, bool>{};
  bool localMetrics = true;
  bool busy = false;

  static const labels = {
    'languages': 'Языковой курс',
    'money': 'Деньги',
    'sport': 'Тренировки',
    'sales': 'Продажи для работы',
  };

  @override
  void initState() {
    super.initState();
    final raw = widget.database.preference('privacy.aiContext');
    final saved = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    for (final id in widget.enabledModules) {
      contextAccess[id] = saved[id] == true;
    }
    localMetrics =
        widget.database.preference('beta.localMetricsEnabled') != false;
  }

  Future<void> _save() async {
    setState(() => busy = true);
    await widget.database.savePreference('privacy.aiContext', contextAccess);
    await widget.database
        .savePreference('beta.localMetricsEnabled', localMetrics);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _clearMetrics() async {
    final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Очистить статистику?'),
            content: const Text(
              'Удалятся только локальные счётчики использования. Записи, деньги, планы и прогресс останутся на месте.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Очистить'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved) return;
    await widget.database.savePreference('beta.metrics', <String, dynamic>{});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Локальная beta-статистика очищена')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.database.preference('beta.metrics');
    final metricCount = metrics is Map ? metrics.length : 0;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.privacy_tip_outlined),
          SizedBox(width: 10),
          Text('Приватность и данные'),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Локальные данные модулей не отправляются помощнику автоматически. Здесь вы заранее выбираете, контекст каких разделов можно будет использовать в будущих подсказках.',
              ),
              const SizedBox(height: 14),
              if (widget.enabledModules.isEmpty)
                const Text('Подключённых модулей пока нет.')
              else
                ...widget.enabledModules.map(
                  (id) => SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(labels[id] ?? id),
                    subtitle: const Text(
                      'Только после явного запроса; изменение данных всё равно требует подтверждения.',
                    ),
                    value: contextAccess[id] ?? false,
                    onChanged: (value) =>
                        setState(() => contextAccess[id] = value),
                  ),
                ),
              const Divider(height: 28),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Локальная beta-статистика'),
                subtitle: const Text(
                  'Считает открытия, завершение настройки и подтверждённые записи. Текст, суммы и названия не записываются и автоматически никуда не отправляются.',
                ),
                value: localMetrics,
                onChanged: (value) => setState(() => localMetrics = value),
              ),
              TextButton.icon(
                onPressed: metricCount == 0 ? null : _clearMetrics,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text('Очистить локальные счётчики ($metricCount)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: busy ? null : _save,
          child: Text(busy ? 'Сохраняем…' : 'Сохранить настройки'),
        ),
      ],
    );
  }
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({required this.manager});
  final SessionManager manager;
  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final message = TextEditingController();
  String category = 'bug';
  String? error;
  bool busy = false;
  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.manager.authenticatedRequest('POST', '/api/feedback', body: {
        'category': category,
        'message': message.text,
        'appVersion': '0.1.0+1',
        'platform': defaultTargetPlatform.name,
        'module': 'quick-capture',
      });
      if (mounted) Navigator.pop(context);
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Beta feedback'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
              value: category,
              items: const [
                DropdownMenuItem(value: 'bug', child: Text('Ошибка')),
                DropdownMenuItem(value: 'idea', child: Text('Идея')),
                DropdownMenuItem(value: 'ux', child: Text('UX')),
                DropdownMenuItem(value: 'other', child: Text('Другое'))
              ],
              onChanged: (value) =>
                  setState(() => category = value ?? category)),
          TextField(
              controller: message,
              onChanged: (_) => setState(() {}),
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Сообщение')),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: busy || message.text.trim().length < 3 ? null : submit,
              child: const Text('Отправить'))
        ],
      );
}

class _AiCreditsDialog extends StatefulWidget {
  const _AiCreditsDialog({required this.manager});
  final SessionManager manager;
  @override
  State<_AiCreditsDialog> createState() => _AiCreditsDialogState();
}

class _AiCreditsDialogState extends State<_AiCreditsDialog> {
  Map<String, dynamic>? balance;
  List<dynamic> history = const [];
  String? error;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = await Future.wait([
        widget.manager.authenticatedRequest('GET', '/api/ai/credits/balance'),
        widget.manager.authenticatedRequest('GET', '/api/ai/credits/history'),
      ]);
      if (mounted) {
        setState(() {
          balance = values[0] as Map<String, dynamic>;
          history = values[1] as List<dynamic>;
        });
      }
    } on ApiFailure catch (value) {
      if (mounted) setState(() => error = value.userMessage);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _historyLabel(String value) => switch (value) {
        'BONUS' => 'Бонус',
        'CHARGE' => 'Использовано',
        'RESERVATION' => 'Подготовка запроса',
        'RESERVATION_RELEASE' => 'Возврат резерва',
        'ADJUSTMENT' => 'Корректировка',
        _ => 'Операция',
      };

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Статус умных функций'),
        content: SizedBox(
          width: 580,
          height: 390,
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : Builder(builder: (context) {
                  final available =
                      (balance?['availableBalance'] as num?)?.toInt() ?? 0;
                  final reserved =
                      (balance?['reservedBalance'] as num?)?.toInt() ?? 0;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              available > 0
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.info_outline_rounded,
                              color: available > 0 ? _green : _amber,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    available > 0
                                        ? 'Умные функции доступны'
                                        : 'Ручной режим работает без ограничений',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    available > 0
                                        ? 'Осталось запросов: $available'
                                        : 'Диалог и автоматическая подготовка могут быть временно недоступны. Записи, история и прогресс продолжают работать.',
                                    style: TextStyle(color: _secondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (reserved > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child:
                                Text('$reserved запр. сейчас обрабатывается'),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          'Проверка финансовой записи перед сохранением остаётся обязательной. Ничего не записывается автоматически.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12),
                        ),
                        const Divider(height: 24),
                        Text('Последние изменения',
                            style: Theme.of(context).textTheme.titleMedium),
                        Expanded(
                          child: history.isEmpty
                              ? const Center(child: Text('История пока пуста'))
                              : ListView(
                                  children: history.map((value) {
                                    final item =
                                        Map<String, dynamic>.from(value as Map);
                                    final amount =
                                        (item['amount'] as num?)?.toInt() ?? 0;
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(_historyLabel(
                                          item['type'] as String? ?? '')),
                                      subtitle:
                                          Text(item['reason'] as String? ?? ''),
                                      trailing: Text(
                                          '${amount > 0 ? '+' : ''}$amount'),
                                    );
                                  }).toList(),
                                ),
                        ),
                        if (error != null)
                          Text(
                            'Не удалось обновить статус. Ручные записи и локальные данные продолжают работать.',
                            style: TextStyle(color: _amber),
                          ),
                      ]);
                }),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : load, child: const Text('Обновить')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть')),
        ],
      );
}
