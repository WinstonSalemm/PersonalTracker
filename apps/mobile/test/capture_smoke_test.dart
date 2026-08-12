import 'package:flutter_test/flutter_test.dart';
import 'package:personal_tracker_command_parser/command_parser.dart';
import 'package:personal_tracker_domain/domain.dart';

void main() {
  test('quick capture covers all four module types', () async {
    final parser = DeterministicParser();
    final expense =
        await parser.parse('Купил бутылку колы за 20 тысяч сум наличными.');
    final call =
        await parser.parse('Позвонил в компанию ABC. Предложил сайт-каталог.');
    final english =
        await parser.parse('Сегодня занимался английским 45 минут.');
    final sports =
        await parser.parse('Играл в настольный теннис полтора часа.');

    expect(expense?.type, CaptureType.expense);
    expect(call?.type, CaptureType.salesCall);
    expect(english?.type, CaptureType.english);
    expect(sports?.type, CaptureType.sports);
  });
}
