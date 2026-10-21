class TableGiftItem {
  const TableGiftItem({
    required this.id,
    required this.nameTr,
    required this.nameEn,
    required this.price,
  });
  final String id, nameTr, nameEn;
  final int price;
  static const ids = {
    'cay',
    'kahve',
    'pasta',
    'kirmizi_gul',
    'limon',
    'aci_biber',
    'sans_yildizi',
    'nazar_boncugu',
    'sans_nali',
    'tac',
    'yuzuk',
    'dort_yaprakli_yonca',
    'saat',
    'hediye_paketi',
  };
  String get asset => 'assets/images/hediyeler/$id.png';
  factory TableGiftItem.fromJson(Map<String, dynamic> row) {
    final id = row['id'] as String;
    if (!ids.contains(id) ||
        row['filename'] != '$id.png' ||
        (row['price'] as num).toInt() <= 0) {
      throw const FormatException('Unknown gift asset or price');
    }
    return TableGiftItem(
      id: id,
      nameTr: row['name_tr'] as String,
      nameEn: row['name_en'] as String,
      price: (row['price'] as num).toInt(),
    );
  }
}

class TableGiftEvent {
  const TableGiftEvent({
    required this.seq,
    required this.tableId,
    required this.senderId,
    required this.recipientId,
    required this.giftId,
    required this.requestId,
  });
  final int seq;
  final String tableId, senderId, recipientId, giftId, requestId;
  String get asset => 'assets/images/hediyeler/$giftId.png';
  factory TableGiftEvent.fromJson(Map<String, dynamic> row) {
    final gift = row['gift_id'] as String;
    if (!TableGiftItem.ids.contains(gift)) {
      throw const FormatException('Unknown gift');
    }
    return TableGiftEvent(
      seq: (row['seq'] as num).toInt(),
      tableId: row['table_id'] as String,
      senderId: row['sender_id'] as String,
      recipientId: row['recipient_id'] as String,
      giftId: gift,
      requestId: row['request_id'] as String,
    );
  }
}

class TableLastGift {
  const TableLastGift(this.seq, this.giftId);
  final int seq;
  final String giftId;
  String get asset => 'assets/images/hediyeler/$giftId.png';
}
