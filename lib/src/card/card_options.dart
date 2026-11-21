import 'card_terminal.dart';

/// Turns on card payments on a physical POS for a payment widget, and says
/// which POS to charge on. Without it the card method is never shown: a
/// device without a POS never offers it.
///
/// ```dart
/// // The POS is registered in Nexus Payments under the device's code:
/// card: const CardOptions(terminalId: 'TOTEM100'),
///
/// // The POS is configured in the app (tests, a device not registered yet):
/// card: const CardOptions.manual(CardTerminalConfig(
///   posIp: '192.168.0.34',
///   posPort: 3000,
///   connection: CardConnection.direct,
/// )),
/// ```
class CardOptions {
  /// The POS registered in Nexus Payments under [terminalId]
  /// (`card_terminal.code`). Its IP and connection are read before showing
  /// the methods, so editing them there applies on the next payment.
  const CardOptions({
    required String this.terminalId,
    this.checkReachability = true,
  })  : config = null,
        terminal = null;

  /// A POS configured in the app. Pass [terminalId] too when it is also
  /// registered, so the payment is recorded with its terminal.
  const CardOptions.manual(
    CardTerminalConfig this.config, {
    this.terminalId,
    this.checkReachability = true,
  }) : terminal = null;

  /// Your own [CardTerminal] (another POS brand, a simulator).
  const CardOptions.custom(
    CardTerminal this.terminal, {
    this.terminalId,
    this.checkReachability = true,
  }) : config = null;

  /// The device's code in Nexus Payments; the payment is recorded with it.
  final String? terminalId;

  /// Set with [CardOptions.manual].
  final CardTerminalConfig? config;

  /// Set with [CardOptions.custom].
  final CardTerminal? terminal;

  /// Hide the card method when the POS (or the local service) doesn't
  /// answer, instead of letting the customer choose it and fail.
  final bool checkReachability;
}
