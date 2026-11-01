import 'reminder_model.dart';

/// The reminders and history on this device (see SqliteReminderStore).
abstract class ReminderStore {
  Future<void> initialize();

  Stream<List<ReminderModel>> watchReminders();
  Future<List<ReminderModel>> listReminders();
  Future<ReminderModel?> getReminder(String id);
  Future<void> upsertReminder(ReminderModel reminder);
  Future<void> upsertReminders(List<ReminderModel> reminders);
  Future<void> deleteReminder(String id);

  Stream<List<ReminderEvent>> watchEvents();
  Future<List<ReminderEvent>> listEvents();
  Future<void> upsertEvent(ReminderEvent event);
  Future<void> upsertEvents(List<ReminderEvent> events);

  Future<void> dispose();
}
