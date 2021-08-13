/// A queue message that couldn't be sent because the sender port doesn't exist
/// yet.
class QueuedMessage extends Object {
  /// The message to send.
  final dynamic message;

  /// The list of transferable objects, if any.
  final List<Object>? transfer;

  QueuedMessage(this.message, [this.transfer]);
}
