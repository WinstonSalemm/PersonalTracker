import 'package:test/test.dart';
import 'package:personal_tracker_command_parser/command_parser.dart';
import 'package:personal_tracker_domain/domain.dart';

void main() {
  final parser = DeterministicParser();

  test('parses a confirmed UZS cash expense', () async {
    final draft = await parser.parse('Купил бутылку колы за 20 тысяч сум наличными.');
    expect(draft?.type, CaptureType.expense);
    expect(draft?.amount, 20000);
    expect(draft?.currency, 'UZS');
    expect(draft?.category, 'drinks');
    expect(draft?.paymentMethod, 'cash');
    expect(draft?.description, 'бутылку колы');
  });

  test('parses a sales call and Friday follow-up', () async {
    final draft = await parser.parse('Позвонил в компанию ABC. Сказали перезвонить в пятницу. Предложил сайт-каталог.');
    expect(draft?.type, CaptureType.salesCall);
    expect(draft?.company, 'ABC');
    expect(draft?.nextStep, 'Перезвонить');
    expect(draft?.followUpDate, isNotNull);
    expect(draft?.offered, contains('сайт-каталог'));
  });

  test('parses English minutes and sports half hour phrase', () async {
    final english = await parser.parse('Сегодня занимался английским 45 минут.');
    final sports = await parser.parse('Играл в настольный теннис полтора часа.');
    expect(english?.type, CaptureType.english);
    expect(english?.durationMinutes, 45);
    expect(sports?.type, CaptureType.sports);
    expect(sports?.durationMinutes, 90);
    expect(sports?.activityType, 'table_tennis');
  });
}
