import 'app_strings.dart';

/// Copy for the grouped Material Return composer (4 November 2026).
abstract final class YorksV1MaterialReturnComposerStrings {
  static const materialToReturn = TranslatableString(
    en: 'Material to return',
    ar: 'المواد المراد إرجاعها',
    ur: 'واپس کرنے کا میٹریل',
    hi: 'वापस की जाने वाली सामग्री',
  );
  static const materialToReturnHint = TranslatableString(
    en: 'Find material delivered to this project and add it. Quantities are taken from the newest delivery first.',
    ar: 'ابحث عن المواد التي تم توريدها لهذا المشروع وأضفها. تؤخذ الكميات من أحدث توريد أولاً.',
    ur: 'اس پروجیکٹ کو بھیجا گیا میٹریل تلاش کریں اور شامل کریں۔ مقدار پہلے تازہ ترین ڈیلیوری سے لی جاتی ہے۔',
    hi: 'इस परियोजना को भेजी गई सामग्री खोजें और जोड़ें। मात्रा पहले सबसे नई डिलीवरी से ली जाती है।',
  );
  static const searchDelivered = TranslatableString(
    en: 'Search delivered material, size, code or MR number',
    ar: 'ابحث عن المادة أو المقاس أو الرمز أو رقم طلب المواد',
    ur: 'بھیجا گیا میٹریل، سائز، کوڈ یا MR نمبر تلاش کریں',
    hi: 'भेजी गई सामग्री, आकार, कोड या MR संख्या खोजें',
  );
  static const add = TranslatableString(
    en: 'Add',
    ar: 'إضافة',
    ur: 'شامل کریں',
    hi: 'जोड़ें',
  );
  static const added = TranslatableString(
    en: 'Added',
    ar: 'تمت الإضافة',
    ur: 'شامل',
    hi: 'जोड़ा गया',
  );
  static const noMatches = TranslatableString(
    en: 'No delivered material matches this search.',
    ar: 'لا توجد مواد موردة تطابق هذا البحث.',
    ur: 'اس تلاش سے کوئی بھیجا گیا میٹریل نہیں ملا۔',
    hi: 'इस खोज से कोई भेजी गई सामग्री मेल नहीं खाती।',
  );
  static const noDelivered = TranslatableString(
    en: 'Nothing delivered to this project can be returned yet.',
    ar: 'لا توجد مواد موردة لهذا المشروع يمكن إرجاعها بعد.',
    ur: 'اس پروجیکٹ کو بھیجا گیا کوئی میٹریل ابھی واپس نہیں ہو سکتا۔',
    hi: 'इस परियोजना को भेजी गई कोई सामग्री अभी वापस नहीं की जा सकती।',
  );
  static const searching = TranslatableString(
    en: 'Searching similar spellings…',
    ar: 'جارٍ البحث عن تهجئات مشابهة…',
    ur: 'ملتے جلتے ہجے تلاش ہو رہے ہیں…',
    hi: 'मिलती-जुलती वर्तनी खोजी जा रही है…',
  );
  static const loadFailed = TranslatableString(
    en: 'Delivered material could not be loaded.',
    ar: 'تعذر تحميل المواد الموردة.',
    ur: 'بھیجا گیا میٹریل لوڈ نہیں ہو سکا۔',
    hi: 'भेजी गई सामग्री लोड नहीं हो सकी।',
  );
  static const retry = TranslatableString(
    en: 'Retry',
    ar: 'إعادة المحاولة',
    ur: 'دوبارہ کوشش',
    hi: 'पुनः प्रयास',
  );
  static const allBuildings = TranslatableString(
    en: 'All buildings',
    ar: 'جميع المباني',
    ur: 'تمام عمارتیں',
    hi: 'सभी इमारतें',
  );
  static TranslatableString onlyBuilding(String name) => TranslatableString(
    en: 'Only $name',
    ar: '$name فقط',
    ur: 'صرف $name',
    hi: 'केवल $name',
  );
  static TranslatableString returnable(String quantity, String unit) =>
      TranslatableString(
        en: '$quantity $unit returnable',
        ar: '$quantity $unit قابلة للإرجاع',
        ur: '$quantity $unit واپسی کے قابل',
        hi: '$quantity $unit वापसी योग्य',
      );
  static TranslatableString unconfirmedPart(String quantity) =>
      TranslatableString(
        en: '$quantity not yet confirmed by site',
        ar: '$quantity لم يؤكدها الموقع بعد',
        ur: '$quantity سائٹ نے ابھی تصدیق نہیں کی',
        hi: '$quantity की साइट ने अभी पुष्टि नहीं की',
      );
  static TranslatableString available(String quantity, String unit) =>
      TranslatableString(
        en: 'Available: $quantity $unit',
        ar: 'المتاح: $quantity $unit',
        ur: 'دستیاب: $quantity $unit',
        hi: 'उपलब्ध: $quantity $unit',
      );
  static TranslatableString exceedsAvailable(String quantity) =>
      TranslatableString(
        en: 'Only $quantity can be returned',
        ar: 'يمكن إرجاع $quantity فقط',
        ur: 'صرف $quantity واپس ہو سکتا ہے',
        hi: 'केवल $quantity वापस की जा सकती है',
      );
  static const quantityRequired = TranslatableString(
    en: 'Enter a quantity above zero',
    ar: 'أدخل كمية أكبر من صفر',
    ur: 'صفر سے زیادہ مقدار درج کریں',
    hi: 'शून्य से अधिक मात्रा दर्ज करें',
  );
  static const noLongerAvailable = TranslatableString(
    en: 'No longer available to return',
    ar: 'لم تعد متاحة للإرجاع',
    ur: 'اب واپسی کے لیے دستیاب نہیں',
    hi: 'अब वापसी के लिए उपलब्ध नहीं',
  );
  static const deliveries = TranslatableString(
    en: 'Deliveries used',
    ar: 'التوريدات المستخدمة',
    ur: 'استعمال شدہ ڈیلیوریاں',
    hi: 'उपयोग की गई डिलीवरी',
  );
  static TranslatableString takes(String quantity, String of) =>
      TranslatableString(
        en: 'Takes $quantity of $of',
        ar: 'يأخذ $quantity من $of',
        ur: '$of میں سے $quantity',
        hi: '$of में से $quantity',
      );
  static const unconfirmedDelivery = TranslatableString(
    en: 'Not yet confirmed by site',
    ar: 'لم يؤكده الموقع بعد',
    ur: 'سائٹ نے ابھی تصدیق نہیں کی',
    hi: 'साइट ने अभी पुष्टि नहीं की',
  );
  static const confirmedDelivery = TranslatableString(
    en: 'Confirmed by site',
    ar: 'أكده الموقع',
    ur: 'سائٹ نے تصدیق کی',
    hi: 'साइट द्वारा पुष्टि',
  );
  static TranslatableString selectedCount(int count) => TranslatableString(
    en: count == 1 ? '1 material selected' : '$count materials selected',
    ar: 'تم اختيار $count من المواد',
    ur: '$count میٹریل منتخب',
    hi: '$count सामग्री चुनी गई',
  );
  static const nothingSelected = TranslatableString(
    en: 'Search above and add the material you are sending back.',
    ar: 'ابحث أعلاه وأضف المواد التي ترجعها.',
    ur: 'اوپر تلاش کریں اور واپس بھیجا جانے والا میٹریل شامل کریں۔',
    hi: 'ऊपर खोजें और वापस भेजी जा रही सामग्री जोड़ें।',
  );
  static const itemsNotDelivered = TranslatableString(
    en: 'Items not from a recorded delivery',
    ar: 'مواد ليست من توريد مسجل',
    ur: 'ایسی اشیاء جو ریکارڈ شدہ ڈیلیوری سے نہیں',
    hi: 'ऐसी वस्तुएँ जो दर्ज डिलीवरी से नहीं हैं',
  );
  static const itemsNotDeliveredHint = TranslatableString(
    en: 'Warehouse maps these to stock on receipt.',
    ar: 'يطابقها المستودع مع المخزون عند الاستلام.',
    ur: 'گودام وصولی پر انہیں اسٹاک سے ملاتا ہے۔',
    hi: 'गोदाम प्राप्ति पर इन्हें स्टॉक से मिलाता है।',
  );
  static const addItem = TranslatableString(
    en: 'Add item',
    ar: 'إضافة مادة',
    ur: 'آئٹم شامل کریں',
    hi: 'वस्तु जोड़ें',
  );
  static const remove = TranslatableString(
    en: 'Remove',
    ar: 'إزالة',
    ur: 'ہٹائیں',
    hi: 'हटाएँ',
  );
  static const material = TranslatableString(
    en: 'Material',
    ar: 'المادة',
    ur: 'میٹریل',
    hi: 'सामग्री',
  );
  static const returnQuantity = TranslatableString(
    en: 'Return qty',
    ar: 'كمية الإرجاع',
    ur: 'واپسی مقدار',
    hi: 'वापसी मात्रा',
  );
  static const lineNote = TranslatableString(
    en: 'Line note',
    ar: 'ملاحظة البند',
    ur: 'لائن نوٹ',
    hi: 'पंक्ति टिप्पणी',
  );
  static const size = TranslatableString(
    en: 'Size',
    ar: 'المقاس',
    ur: 'سائز',
    hi: 'आकार',
  );
  static const model = TranslatableString(
    en: 'Model',
    ar: 'الطراز',
    ur: 'ماڈل',
    hi: 'मॉडल',
  );
  static const code = TranslatableString(
    en: 'Code',
    ar: 'الرمز',
    ur: 'کوڈ',
    hi: 'कोड',
  );
  static const equipmentTag = TranslatableString(
    en: 'Equipment tag',
    ar: 'رمز المعدة',
    ur: 'ایکوپمنٹ ٹیگ',
    hi: 'उपकरण टैग',
  );
  static const fixHighlighted = TranslatableString(
    en: 'Some quantities need attention. Adjust the highlighted lines.',
    ar: 'بعض الكميات تحتاج إلى مراجعة. عدّل البنود المميزة.',
    ur: 'کچھ مقداروں پر توجہ درکار ہے۔ نمایاں لائنیں درست کریں۔',
    hi: 'कुछ मात्राओं पर ध्यान चाहिए। हाइलाइट की गई पंक्तियाँ ठीक करें।',
  );
  static const quantityTaken = TranslatableString(
    en: 'Someone else has just returned part of this material. Refresh and adjust the quantities.',
    ar: 'قام شخص آخر للتو بإرجاع جزء من هذه المادة. حدّث الصفحة وعدّل الكميات.',
    ur: 'کسی اور نے ابھی اس میٹریل کا کچھ حصہ واپس کیا ہے۔ ریفریش کریں اور مقدار درست کریں۔',
    hi: 'किसी और ने अभी इस सामग्री का कुछ भाग वापस किया है। रिफ्रेश करें और मात्रा ठीक करें।',
  );
  static const receiptBelowReturns = TranslatableString(
    en: 'This receipt records less good material than is already on Material Returns from this delivery. Reduce or cancel the return first.',
    ar: 'يسجل هذا الاستلام كمية سليمة أقل مما هو مدرج في مرتجعات المواد من هذا التوريد. قلّل المرتجع أو ألغِه أولاً.',
    ur: 'یہ وصولی اس ڈیلیوری کے میٹریل ریٹرن میں موجود مقدار سے کم درست میٹریل درج کرتی ہے۔ پہلے واپسی کم یا منسوخ کریں۔',
    hi: 'यह प्राप्ति इस डिलीवरी से सामग्री वापसी में पहले से दर्ज मात्रा से कम सही सामग्री दर्ज करती है। पहले वापसी कम या रद्द करें।',
  );
}
