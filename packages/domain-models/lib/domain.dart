enum CaptureType { expense, income, salesCall, english, sports }

extension CaptureTypeLabel on CaptureType {
  String get wireName => switch (this) {
    CaptureType.expense => 'expense',
    CaptureType.income => 'income',
    CaptureType.salesCall => 'sales_call',
    CaptureType.english => 'english',
    CaptureType.sports => 'sports',
  };
}

class CaptureDraft {
  const CaptureDraft({
    required this.type,
    required this.originalText,
    required this.date,
    this.amount,
    this.currency = 'UZS',
    this.category,
    this.paymentMethod,
    this.description,
    this.company,
    this.result,
    this.whatSaid,
    this.offered,
    this.nextStep,
    this.followUpDate,
    this.durationMinutes,
    this.activityType,
    this.completedTask,
    this.comment,
  });

  final CaptureType type;
  final String originalText;
  final String date;
  final double? amount;
  final String currency;
  final String? category;
  final String? paymentMethod;
  final String? description;
  final String? company;
  final String? result;
  final String? whatSaid;
  final String? offered;
  final String? nextStep;
  final String? followUpDate;
  final int? durationMinutes;
  final String? activityType;
  final String? completedTask;
  final String? comment;

  Map<String, Object?> toJson() => {
    'type': type.wireName,
    'originalText': originalText,
    'date': date,
    'amount': amount,
    'currency': currency,
    'category': category,
    'paymentMethod': paymentMethod,
    'description': description,
    'company': company,
    'result': result,
    'whatSaid': whatSaid,
    'offered': offered,
    'nextStep': nextStep,
    'followUpDate': followUpDate,
    'durationMinutes': durationMinutes,
    'activityType': activityType,
    'completedTask': completedTask,
    'comment': comment,
  };
}

class CaptureRecord {
  const CaptureRecord({
    required this.id,
    required this.draft,
    required this.createdAt,
    this.syncedAt,
  });

  final String id;
  final CaptureDraft draft;
  final DateTime createdAt;
  final DateTime? syncedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'syncedAt': syncedAt?.toUtc().toIso8601String(),
    'payload': draft.toJson(),
  };
}

enum MoneyTransactionType { income, expense, transfer }
enum MoneyPaymentMethod { cash, card, bank, other }
enum MoneyTransactionStatus { completed, planned, expected }
enum MoneyRecurrence { weekly, monthly, quarterly, yearly }
enum MoneyAccountType { cash, card, bank, wallet }
enum MoneyCategoryKind { income, expense }

String _moneyEnumValue(Object value) => value.toString().split('.').last;

MoneyTransactionType moneyTransactionTypeFrom(String value) => MoneyTransactionType.values.firstWhere(
      (item) => _moneyEnumValue(item) == value,
      orElse: () => MoneyTransactionType.expense,
    );

MoneyPaymentMethod moneyPaymentMethodFrom(String value) => MoneyPaymentMethod.values.firstWhere(
      (item) => _moneyEnumValue(item) == value,
      orElse: () => MoneyPaymentMethod.cash,
    );

MoneyTransactionStatus moneyTransactionStatusFrom(String value) => MoneyTransactionStatus.values.firstWhere(
      (item) => _moneyEnumValue(item) == value,
      orElse: () => MoneyTransactionStatus.completed,
    );

MoneyRecurrence? moneyRecurrenceFrom(String? value) => value == null
    ? null
    : MoneyRecurrence.values.cast<MoneyRecurrence?>().firstWhere(
        (item) => _moneyEnumValue(item!) == value,
        orElse: () => null,
      );

MoneyAccountType moneyAccountTypeFrom(String value) => MoneyAccountType.values.firstWhere(
      (item) => _moneyEnumValue(item) == value,
      orElse: () => MoneyAccountType.cash,
    );

MoneyCategoryKind moneyCategoryKindFrom(String value) => MoneyCategoryKind.values.firstWhere(
      (item) => _moneyEnumValue(item) == value,
      orElse: () => MoneyCategoryKind.expense,
    );

class MoneyAccount {
  const MoneyAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.initialBalance,
    required this.color,
    required this.createdAt,
  });

  final String id;
  final String name;
  final MoneyAccountType type;
  final String currency;
  final double initialBalance;
  final String color;
  final DateTime createdAt;
}

class MoneyCategory {
  const MoneyCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.color,
    this.system = true,
  });

  final String id;
  final String name;
  final MoneyCategoryKind kind;
  final String color;
  final bool system;
}

class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.currency,
    required this.counterparty,
    required this.categoryId,
    required this.purpose,
    required this.paymentMethod,
    required this.accountId,
    required this.recurring,
    required this.status,
    required this.comment,
    required this.createdAt,
    this.transferToAccountId,
    this.incomeSource,
    this.obligationId,
    this.essential = true,
  });

  final String id;
  final String date;
  final MoneyTransactionType type;
  final double amount;
  final String currency;
  final String counterparty;
  final String categoryId;
  final String purpose;
  final MoneyPaymentMethod paymentMethod;
  final String accountId;
  final String? transferToAccountId;
  final bool recurring;
  final MoneyTransactionStatus status;
  final String? incomeSource;
  final String? obligationId;
  final bool essential;
  final String comment;
  final DateTime createdAt;
}

class MoneyObligation {
  const MoneyObligation({
    required this.id,
    required this.name,
    required this.totalAmount,
    required this.paidAmount,
    required this.currency,
    required this.dueDate,
    required this.comment,
    required this.status,
    this.recurrence,
  });

  final String id;
  final String name;
  final double totalAmount;
  final double paidAmount;
  final String currency;
  final String dueDate;
  final MoneyRecurrence? recurrence;
  final String comment;
  final String status;
}

class MoneyRecurringTemplate {
  const MoneyRecurringTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.amount,
    required this.currency,
    required this.counterparty,
    required this.categoryId,
    required this.accountId,
    required this.nextDate,
    required this.recurrence,
    required this.status,
  });

  final String id;
  final String name;
  final MoneyTransactionType type;
  final double amount;
  final String currency;
  final String counterparty;
  final String categoryId;
  final String accountId;
  final String nextDate;
  final MoneyRecurrence recurrence;
  final String status;
}

class AssistantTask {
  const AssistantTask({
    required this.id,
    required this.title,
    required this.originalText,
    required this.createdAt,
    this.dueAt,
    this.notes = '',
    this.status = 'planned',
  });

  final String id;
  final String title;
  final String originalText;
  final DateTime createdAt;
  final DateTime? dueAt;
  final String notes;
  final String status;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'originalText': originalText,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'dueAt': dueAt?.toUtc().toIso8601String(),
    'notes': notes,
    'status': status,
  };
}

class AssistantContact {
  const AssistantContact({
    required this.id,
    required this.name,
    required this.createdAt,
    this.phone,
    this.telegramUsername,
  });

  final String id;
  final String name;
  final String? phone;
  final String? telegramUsername;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'telegramUsername': telegramUsername,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}
