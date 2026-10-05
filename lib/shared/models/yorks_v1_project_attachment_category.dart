/// Optional organization of local setup attachments. These labels do not
/// authorize access or choose a protected document security classification.
enum YorksV1ProjectAttachmentCategory {
  general('general'),
  drawing('drawing'),
  calculation('calculation'),
  schedule('schedule'),
  approval('approval'),
  materialList('material_list'),
  other('other');

  const YorksV1ProjectAttachmentCategory(this.wireValue);
  final String wireValue;

  static YorksV1ProjectAttachmentCategory? fromWireValue(Object? value) {
    if (value is! String) return null;
    for (final category in values) {
      if (category.wireValue == value) return category;
    }
    return null;
  }
}
