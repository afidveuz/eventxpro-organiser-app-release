class TicketTypeModel {
  final int pk;
  final String label;
  final String? ticketTypeCat;
  final num? price;
  final String? currency;
  final String? description;
  final int? quantity;
  final int? remaining;

  const TicketTypeModel({
    required this.pk,
    required this.label,
    this.ticketTypeCat,
    this.price,
    this.currency,
    this.description,
    this.quantity,
    this.remaining,
  });

  factory TicketTypeModel.fromJson(Map<String, dynamic> json) {
    // pk can be int or string or under 'id'
    final rawPk = json['pk'] ?? json['id'] ?? json['ticket_id'] ?? 0;
    final parsedPk = rawPk is int ? rawPk : int.tryParse(rawPk.toString()) ?? 0;

    final rawLabel = json['label'] ??
        json['ticket_name'] ??
        json['name'] ??
        json['title'] ??
        'Ticket #$parsedPk';

    num? parsedPrice;
    if (json['price'] != null) {
      if (json['price'] is num) {
        parsedPrice = json['price'] as num;
      } else {
        parsedPrice = num.tryParse(json['price'].toString());
      }
    }

    return TicketTypeModel(
      pk: parsedPk,
      label: rawLabel.toString().trim(),
      ticketTypeCat: json['ticket_type_cat']?.toString() ??
          json['category']?.toString() ??
          json['type']?.toString(),
      price: parsedPrice,
      currency: json['currency']?.toString(),
      description: json['description']?.toString(),
      quantity: json['quantity'] is int
          ? json['quantity'] as int
          : int.tryParse(json['quantity']?.toString() ?? ''),
      remaining: json['remaining'] is int
          ? json['remaining'] as int
          : int.tryParse(json['remaining']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pk': pk,
      'label': label,
      if (ticketTypeCat != null) 'ticket_type_cat': ticketTypeCat,
      if (price != null) 'price': price,
      if (currency != null) 'currency': currency,
      if (description != null) 'description': description,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TicketTypeModel &&
          runtimeType == other.runtimeType &&
          pk == other.pk;

  @override
  int get hashCode => pk.hashCode;
}
