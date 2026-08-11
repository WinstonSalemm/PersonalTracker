import 'package:test/test.dart';
import 'package:personal_tracker_command_parser/command_parser.dart';

void main() {
  final parser = DeterministicAssistantParser();

  test('parses the requested movie count and genre', () async {
    final plan = await parser.parse('Подбери 3 комедии на вечер');

    expect(plan?.intent, AssistantIntent.movies);
    expect(plan?.movies, hasLength(3));
    expect(plan!.movies.every((movie) => movie.tags.contains('комедия')), isTrue);
  });

  test('parses a task date and time', () async {
    final plan = await parser.parse('Поставь задачу купить молоко завтра в 19:30');

    expect(plan?.intent, AssistantIntent.task);
    expect(plan?.taskTitle, 'Купить молоко');
    expect(plan?.dueAt?.hour, 19);
    expect(plan?.dueAt?.minute, 30);
  });

  test('parses a phone call target', () async {
    final plan = await parser.parse('Позвони Ивану +998 90 123 45 67');

    expect(plan?.intent, AssistantIntent.call);
    expect(plan?.phone, '+998901234567');
    expect(plan?.contactName, 'Ивану');
  });

  test('parses a Telegram username and message', () async {
    final plan = await parser.parse('Напиши @alex в Telegram сообщение: Буду через час');

    expect(plan?.intent, AssistantIntent.telegram);
    expect(plan?.telegramUsername, 'alex');
    expect(plan?.message, 'Буду через час');
  });

  test('keeps a named Telegram contact target', () async {
    final plan = await parser.parse('Напиши мама в Telegram сообщение: Я уже дома');

    expect(plan?.intent, AssistantIntent.telegram);
    expect(plan?.contactName, 'мама');
    expect(plan?.message, 'Я уже дома');
  });

  test('parses a visual animal request', () async {
    final plan = await parser.parse('А как выглядит лев?');

    expect(plan?.intent, AssistantIntent.visual);
    expect(plan?.visualQuery, 'лев');
  });

  test('parses a named contact to save locally', () async {
    final plan = await parser.parse('Запомни контакт мама +998 90 123 45 67');

    expect(plan?.intent, AssistantIntent.contact);
    expect(plan?.contactName, 'мама');
    expect(plan?.phone, '+998901234567');
  });
}
