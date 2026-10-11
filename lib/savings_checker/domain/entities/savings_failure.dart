enum SavingsFailureKind {
  rateLimited,
  serviceUnavailable,
  timeout,
  networkError,
  authenticationError,
  parseError,
  configurationError,
  storageError,
}

/// Safe across presentation/logging boundaries: never contains raw responses,
/// request URLs, credentials or the original exception text.
class SavingsFailure implements Exception {
  const SavingsFailure(this.kind);
  final SavingsFailureKind kind;

  String get message => switch (kind) {
    SavingsFailureKind.rateLimited =>
      'Il servizio ha raggiunto temporaneamente il limite di richieste. Puoi riprovare.',
    SavingsFailureKind.serviceUnavailable =>
      'Il servizio AI è temporaneamente occupato. Puoi riprovare.',
    SavingsFailureKind.timeout =>
      'Il servizio sta impiegando troppo tempo a rispondere. Puoi riprovare.',
    SavingsFailureKind.networkError => 'Controlla la connessione e riprova.',
    SavingsFailureKind.authenticationError ||
    SavingsFailureKind.configurationError =>
      'Il servizio AI non è configurato correttamente.',
    SavingsFailureKind.parseError =>
      'Non sono riuscito a interpretare la risposta. Puoi riprovare.',
    SavingsFailureKind.storageError =>
      'Non riesco a leggere o salvare i prezzi sul dispositivo.',
  };

  @override
  String toString() => 'SavingsFailure(${kind.name})';
}
