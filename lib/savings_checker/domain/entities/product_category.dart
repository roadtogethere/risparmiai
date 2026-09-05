enum ProductCategory {
  pantry,
  household,
  bakery,
  beverage,
  personalCare,
  other;

  String get label {
    switch (this) {
      case ProductCategory.pantry:
        return 'Alimentare';
      case ProductCategory.household:
        return 'Casa';
      case ProductCategory.bakery:
        return 'Pane e prodotti da forno';
      case ProductCategory.beverage:
        return 'Bevande';
      case ProductCategory.personalCare:
        return 'Cura personale';
      case ProductCategory.other:
        return 'Altro';
    }
  }
}
