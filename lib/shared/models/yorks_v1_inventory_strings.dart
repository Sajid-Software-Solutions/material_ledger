import 'app_strings.dart';

/// Centralized R38.3 warehouse copy. No operational warehouse surface owns
/// literal user-facing text, so locale expansion remains a data-only change.
abstract final class YorksV1InventoryStrings {
  static const previousPage = TranslatableString(
    en: 'Previous',
    ar: 'السابق',
    ur: 'پچھلا',
    hi: 'पिछला',
  );
  static const nextPage = TranslatableString(
    en: 'Next',
    ar: 'التالي',
    ur: 'اگلا',
    hi: 'अगला',
  );
  static const saveRejected = TranslatableString(
    en: 'The server rejected this save. Review the current stock and your access before trying again.',
    ar: 'رفض الخادم هذا الحفظ. راجع المخزون الحالي وصلاحياتك قبل المحاولة مجددًا.',
    ur: 'سرور نے یہ تبدیلی مسترد کر دی۔ دوبارہ کوشش سے پہلے موجودہ اسٹاک اور اجازتیں دیکھیں۔',
    hi: 'सर्वर ने यह सेव अस्वीकार किया। फिर कोशिश करने से पहले स्टॉक और अपनी अनुमति जाँचें।',
  );
  static const refreshedAt = TranslatableString(
    en: 'Stock checked',
    ar: 'تم فحص المخزون',
    ur: 'اسٹاک چیک کیا گیا',
    hi: 'स्टॉक जाँचा गया',
  );
  static const refreshing = TranslatableString(
    en: 'Refreshing stock…',
    ar: 'جارٍ تحديث المخزون…',
    ur: 'اسٹاک تازہ کیا جا رہا ہے…',
    hi: 'स्टॉक अपडेट हो रहा है…',
  );
  static const dateRange = TranslatableString(
    en: 'Date range',
    ar: 'الفترة الزمنية',
    ur: 'تاریخ کی حد',
    hi: 'तारीख सीमा',
  );
  static const allDates = TranslatableString(
    en: 'All dates',
    ar: 'كل التواريخ',
    ur: 'تمام تاریخیں',
    hi: 'सभी तारीखें',
  );
  static const printMovements = TranslatableString(
    en: 'Print matching movements',
    ar: 'طباعة الحركات المطابقة',
    ur: 'متعلقہ نقل و حرکت پرنٹ کریں',
    hi: 'मिलती गतिविधियाँ प्रिंट करें',
  );
  static const recoveryBlocked = TranslatableString(
    en: 'A saved stock operation could not be read. Contact an administrator before making another stock change. The saved record has been preserved.',
    ar: 'تعذر قراءة عملية مخزون محفوظة. اتصل بالمسؤول قبل إجراء تغيير آخر. تم الاحتفاظ بالسجل.',
    ur: 'محفوظ اسٹاک کارروائی نہیں پڑھی جا سکی۔ مزید تبدیلی سے پہلے منتظم سے رابطہ کریں۔ ریکارڈ محفوظ ہے۔',
    hi: 'सहेजी गई स्टॉक कार्रवाई पढ़ी नहीं जा सकी। अगला बदलाव करने से पहले व्यवस्थापक से संपर्क करें। रिकॉर्ड सुरक्षित है।',
  );
  static const uncertainSave = TranslatableString(
    en: 'The result is not confirmed. Keep this screen open and retry the same save to check its result.',
    ar: 'لم يتم تأكيد النتيجة. أبقِ هذه الشاشة مفتوحة وأعد محاولة الحفظ نفسه للتحقق من النتيجة.',
    ur: 'نتیجے کی تصدیق نہیں ہوئی۔ یہ اسکرین کھلی رکھیں اور نتیجہ جاننے کے لیے وہی محفوظ کاری دوبارہ آزمائیں۔',
    hi: 'परिणाम की पुष्टि नहीं हुई। यह स्क्रीन खुली रखें और परिणाम जाँचने के लिए उसी सेव को फिर से आज़माएँ।',
  );
  static const retrySave = TranslatableString(
    en: 'Retry save',
    ar: 'إعادة الحفظ',
    ur: 'دوبارہ محفوظ کریں',
    hi: 'फिर से सेव करें',
  );
  static const loadFailed = TranslatableString(
    en: 'Stock could not be loaded. Try again.',
    ar: 'تعذر تحميل المخزون. حاول مرة أخرى.',
    ur: 'اسٹاک لوڈ نہیں ہو سکا۔ دوبارہ کوشش کریں۔',
    hi: 'स्टॉक लोड नहीं हो सका। फिर कोशिश करें।',
  );
  static const older = TranslatableString(
    en: 'Older movements',
    ar: 'حركات أقدم',
    ur: 'پرانی نقل و حرکت',
    hi: 'पुराने मूवमेंट',
  );
  static const newer = TranslatableString(
    en: 'Newer movements',
    ar: 'حركات أحدث',
    ur: 'نئی نقل و حرکت',
    hi: 'नए मूवमेंट',
  );
  static const exportMovements = TranslatableString(
    en: 'Export matching movements',
    ar: 'تصدير الحركات المطابقة',
    ur: 'مطابق نقل و حرکت برآمد کریں',
    hi: 'मिलते मूवमेंट निर्यात करें',
  );
  static const noMinimum = TranslatableString(
    en: 'No minimum set',
    ar: 'لم يحدد الحد الأدنى',
    ur: 'کم از کم حد مقرر نہیں',
    hi: 'न्यूनतम तय नहीं',
  );
  static const filters = TranslatableString(
    en: 'Filters',
    ar: 'عوامل التصفية',
    ur: 'فلٹرز',
    hi: 'फ़िल्टर',
  );
  static const exportMatchingStock = TranslatableString(
    en: 'Export stock',
    ar: 'تصدير المخزون',
    ur: 'اسٹاک برآمد کریں',
    hi: 'स्टॉक निर्यात करें',
  );
  static const warehouse = TranslatableString(
    en: 'Warehouse',
    ar: 'المستودع',
    ur: 'گودام',
    hi: 'वेयरहाउस',
  );
  static const warehouseInventory = TranslatableString(
    en: 'Warehouse Inventory',
    ar: 'مخزون المستودع',
    ur: 'گودام انوینٹری',
    hi: 'वेयरहाउस इन्वेंटरी',
  );
  static const procurementWorkspace = TranslatableString(
    en: 'PROCUREMENT WORKSPACE',
    ar: 'مساحة عمل المشتريات',
    ur: 'خریداری ورک اسپیس',
    hi: 'खरीद कार्यक्षेत्र',
  );
  static const subtitle = TranslatableString(
    en: 'Control physical stock, active reservations and every quantity-changing movement from one dependable workspace.',
    ar: 'المخزون المباشر والحجوزات وسجل الحركات',
    ur: 'لائیو اسٹاک، ریزرویشن اور حرکت کی تاریخ',
    hi: 'लाइव स्टॉक, आरक्षण और मूवमेंट इतिहास',
  );
  static const readOnlyInventoryAccess = TranslatableString(
    en: 'Read-only warehouse visibility. Stock and catalogue changes remain controlled by Procurement.',
    ar: 'عرض المستودع للقراءة فقط. تظل تغييرات المخزون والفهرس تحت سيطرة المشتريات.',
    ur: 'گودام صرف دیکھنے کے لیے دستیاب ہے۔ اسٹاک اور کیٹلاگ کی تبدیلیاں پروکیورمنٹ کے زیرِ اختیار رہیں گی۔',
    hi: 'वेयरहाउस केवल देखने के लिए उपलब्ध है। स्टॉक और कैटलॉग बदलाव प्रोक्योरमेंट के नियंत्रण में रहते हैं।',
  );
  static const overview = TranslatableString(
    en: 'Overview',
    ar: 'نظرة عامة',
    ur: 'جائزہ',
    hi: 'अवलोकन',
  );
  static const items = TranslatableString(
    en: 'Items',
    ar: 'الأصناف',
    ur: 'آئٹمز',
    hi: 'आइटम',
  );
  static const item = TranslatableString(
    en: 'Item',
    ar: 'الصنف',
    ur: 'آئٹم',
    hi: 'आइटम',
  );
  static const movements = TranslatableString(
    en: 'Stock Movements',
    ar: 'حركات المخزون',
    ur: 'اسٹاک کی حرکات',
    hi: 'स्टॉक मूवमेंट',
  );
  static const reservations = TranslatableString(
    en: 'Reservations',
    ar: 'الحجوزات',
    ur: 'ریزرویشنز',
    hi: 'आरक्षण',
  );
  static const totalItems = TranslatableString(
    en: 'Total items',
    ar: 'إجمالي الأصناف',
    ur: 'کل آئٹمز',
    hi: 'कुल आइटम',
  );
  static const activeStockItems = TranslatableString(
    en: 'Active Stock Items',
    ar: 'أصناف المخزون النشطة',
    ur: 'فعال اسٹاک آئٹمز',
    hi: 'सक्रिय स्टॉक आइटम',
  );
  static const itemsWithReservations = TranslatableString(
    en: 'Items With Reservations',
    ar: 'أصناف عليها حجوزات',
    ur: 'ریزرویشن والے آئٹمز',
    hi: 'आरक्षण वाले आइटम',
  );
  static const availableStock = TranslatableString(
    en: 'Available stock',
    ar: 'المخزون المتاح',
    ur: 'دستیاب اسٹاک',
    hi: 'उपलब्ध स्टॉक',
  );
  static const reservedStock = TranslatableString(
    en: 'Reserved stock',
    ar: 'المخزون المحجوز',
    ur: 'محفوظ اسٹاک',
    hi: 'आरक्षित स्टॉक',
  );
  static const needsAttention = TranslatableString(
    en: 'Needs Procurement Attention',
    ar: 'يحتاج إلى انتباه',
    ur: 'توجہ درکار',
    hi: 'ध्यान आवश्यक',
  );
  static const stockFormula = TranslatableString(
    en: 'Stock quantity remains controlled',
    ar: 'المتاح = الموجود - المحجوز',
    ur: 'دستیاب = موجود - محفوظ',
    hi: 'उपलब्ध = ऑन हैंड - आरक्षित',
  );
  static const formulaHelp = TranslatableString(
    en: 'On Hand physical stock - Reserved active commitments = Available to arrange or dispatch. Reserved is read-only here and changes only through the Material Request lifecycle.',
    ar: 'تحمي الحجوزات الطلبات المعتمدة. تضيف عمليات الاستيراد والتعديل حركة مخزون دائماً.',
    ur: 'ریزرویشن منظور شدہ درخواستوں کو محفوظ رکھتے ہیں۔ درآمد اور ایڈجسٹمنٹ ہمیشہ اسٹاک موومنٹ شامل کرتے ہیں۔',
    hi: 'आरक्षण स्वीकृत अनुरोधों की रक्षा करते हैं। आयात और समायोजन हमेशा स्टॉक मूवमेंट जोड़ते हैं।',
  );
  static const onHand = TranslatableString(
    en: 'On Hand',
    ar: 'الموجود',
    ur: 'موجود',
    hi: 'ऑन हैंड',
  );
  static const reserved = TranslatableString(
    en: 'Reserved',
    ar: 'المحجوز',
    ur: 'محفوظ',
    hi: 'आरक्षित',
  );
  static const quickTools = TranslatableString(
    en: 'Quick Tools',
    ar: 'أدوات سريعة',
    ur: 'فوری ٹولز',
    hi: 'त्वरित टूल',
  );
  static const addReceive = TranslatableString(
    en: 'Add / Receive Stock',
    ar: 'إضافة / استلام مخزون',
    ur: 'اسٹاک شامل / وصول کریں',
    hi: 'स्टॉक जोड़ें / प्राप्त करें',
  );
  static const addStock = TranslatableString(
    en: 'Add stock',
    ar: 'إضافة مخزون',
    ur: 'اسٹاک شامل کریں',
    hi: 'स्टॉक जोड़ें',
  );
  static const removeStock = TranslatableString(
    en: 'Remove stock',
    ar: 'خصم مخزون',
    ur: 'اسٹاک نکالیں',
    hi: 'स्टॉक हटाएं',
  );
  static const importInventory = TranslatableString(
    en: 'Import Inventory',
    ar: 'استيراد المخزون',
    ur: 'انوینٹری درآمد کریں',
    hi: 'इन्वेंटरी आयात करें',
  );
  static const downloadFormat = TranslatableString(
    en: 'Download Format',
    ar: 'تنزيل النموذج',
    ur: 'فارمیٹ ڈاؤن لوڈ کریں',
    hi: 'फ़ॉर्मेट डाउनलोड करें',
  );
  static const downloadFormatComplete = TranslatableString(
    en: 'The controlled import format was downloaded.',
    ar: 'تم تنزيل نموذج الاستيراد المنضبط.',
    ur: 'کنٹرول شدہ امپورٹ فارمیٹ ڈاؤن لوڈ ہو گیا۔',
    hi: 'नियंत्रित इम्पोर्ट फ़ॉर्मेट डाउनलोड हो गया।',
  );
  static const downloadFormatFailed = TranslatableString(
    en: 'The import format could not be downloaded. Please try again.',
    ar: 'تعذر تنزيل نموذج الاستيراد. يرجى المحاولة مرة أخرى.',
    ur: 'امپورٹ فارمیٹ ڈاؤن لوڈ نہیں ہو سکا۔ دوبارہ کوشش کریں۔',
    hi: 'इम्पोर्ट फ़ॉर्मेट डाउनलोड नहीं हो सका। फिर प्रयास करें।',
  );
  static const downloadImportFormat = TranslatableString(
    en: 'Download Import Format',
    ar: 'تنزيل نموذج الاستيراد',
    ur: 'درآمدی فارمیٹ ڈاؤن لوڈ کریں',
    hi: 'आयात प्रारूप डाउनलोड करें',
  );
  static const chooseControlledAction = TranslatableString(
    en: 'Choose the controlled action you need. Stock quantities are changed only through movements.',
    ar: 'اختر الإجراء المنضبط المطلوب. تتغير الكميات فقط من خلال الحركات.',
    ur: 'مطلوبہ کنٹرول شدہ عمل منتخب کریں۔ مقدار صرف موومنٹس سے بدلتی ہے۔',
    hi: 'आवश्यक नियंत्रित कार्रवाई चुनें। मात्रा केवल मूवमेंट से बदलती है।',
  );
  static const createInventoryItem = TranslatableString(
    en: 'Create inventory item',
    ar: 'إنشاء صنف مخزون',
    ur: 'انوینٹری آئٹم بنائیں',
    hi: 'इन्वेंटरी आइटम बनाएं',
  );
  static const createInventoryItemHelp = TranslatableString(
    en: 'Add the item master and optionally record its opening balance.',
    ar: 'أضف سجل الصنف وسجّل الرصيد الافتتاحي اختيارياً.',
    ur: 'آئٹم ماسٹر شامل کریں اور اختیاری طور پر اوپننگ بیلنس درج کریں۔',
    hi: 'आइटम मास्टर जोड़ें और वैकल्पिक रूप से शुरुआती शेष दर्ज करें।',
  );
  static const itemDetails = TranslatableString(
    en: 'Item Details',
    ar: 'تفاصيل الصنف',
    ur: 'آئٹم کی تفصیلات',
    hi: 'आइटम विवरण',
  );
  static const editInventoryItem = TranslatableString(
    en: 'Edit Inventory Item',
    ar: 'تعديل صنف المخزون',
    ur: 'انوینٹری آئٹم میں ترمیم کریں',
    hi: 'इन्वेंटरी आइटम संपादित करें',
  );
  static const editInventoryItemHelp = TranslatableString(
    en: 'Metadata only; stock remains movement-controlled.',
    ar: 'بيانات تعريفية فقط؛ تظل الكمية محكومة بالحركات.',
    ur: 'صرف میٹا ڈیٹا؛ اسٹاک حرکات کے ذریعے کنٹرول ہوتا ہے۔',
    hi: 'केवल मेटाडेटा; स्टॉक मूवमेंट द्वारा नियंत्रित रहता है।',
  );
  static const editDetails = TranslatableString(
    en: 'Edit Details',
    ar: 'تعديل التفاصيل',
    ur: 'تفصیلات میں ترمیم کریں',
    hi: 'विवरण संपादित करें',
  );
  static const saveItemDetails = TranslatableString(
    en: 'Save Item Details',
    ar: 'حفظ تفاصيل الصنف',
    ur: 'آئٹم کی تفصیلات محفوظ کریں',
    hi: 'आइटम विवरण सहेजें',
  );
  static const receiveAdjust = TranslatableString(
    en: 'Receive / Adjust',
    ar: 'استلام / تعديل',
    ur: 'وصول / ایڈجسٹ',
    hi: 'प्राप्त / समायोजित',
  );
  static const lastUpdated = TranslatableString(
    en: 'Last updated',
    ar: 'آخر تحديث',
    ur: 'آخری اپ ڈیٹ',
    hi: 'अंतिम अपडेट',
  );
  static const notConfigured = TranslatableString(
    en: 'Not configured',
    ar: 'غير مهيأ',
    ur: 'ترتیب نہیں دیا گیا',
    hi: 'कॉन्फ़िगर नहीं है',
  );
  static const adjustExistingStock = TranslatableString(
    en: 'Receive or adjust existing stock',
    ar: 'استلام أو تعديل مخزون موجود',
    ur: 'موجودہ اسٹاک وصول یا ایڈجسٹ کریں',
    hi: 'मौजूदा स्टॉक प्राप्त या समायोजित करें',
  );
  static const adjustExistingStockHelp = TranslatableString(
    en: 'Record stock in, stock out or a controlled correction.',
    ar: 'سجّل الإدخال أو الإخراج أو التصحيح المنضبط.',
    ur: 'اسٹاک اِن، آؤٹ یا کنٹرول شدہ تصحیح درج کریں۔',
    hi: 'स्टॉक इन, आउट या नियंत्रित सुधार दर्ज करें।',
  );
  static const movementTrust = TranslatableString(
    en: 'Current on hand is never edited directly. Every change records the actor, time, reason and resulting balance.',
    ar: 'لا يتم تعديل الموجود مباشرة. كل تغيير يسجل المنفذ والوقت والسبب والرصيد الناتج.',
    ur: 'موجودہ مقدار براہ راست تبدیل نہیں ہوتی۔ ہر تبدیلی عامل، وقت، وجہ اور نتیجہ درج کرتی ہے۔',
    hi: 'ऑन हैंड सीधे संपादित नहीं होता। हर बदलाव कर्ता, समय, कारण और परिणाम दर्ज करता है।',
  );
  static const itemIdentity = TranslatableString(
    en: 'Item identity',
    ar: 'هوية الصنف',
    ur: 'آئٹم شناخت',
    hi: 'आइटम पहचान',
  );
  static const itemCodeOptional = TranslatableString(
    en: 'Item code optional',
    ar: 'رمز الصنف اختياري',
    ur: 'آئٹم کوڈ اختیاری',
    hi: 'आइटम कोड वैकल्पिक',
  );
  static const autoGenerated = TranslatableString(
    en: 'Auto-generated when blank',
    ar: 'يتم إنشاؤه تلقائياً عند تركه فارغاً',
    ur: 'خالی ہونے پر خود بنے گا',
    hi: 'खाली होने पर स्वतः बनेगा',
  );
  static const materialEquipmentDescription = TranslatableString(
    en: 'Material or equipment description',
    ar: 'وصف المادة أو المعدة',
    ur: 'مواد یا سامان کی تفصیل',
    hi: 'सामग्री या उपकरण का विवरण',
  );
  static const size = TranslatableString(
    en: 'Size',
    ar: 'المقاس',
    ur: 'سائز',
    hi: 'आकार',
  );
  static const modelReference = TranslatableString(
    en: 'Model / equipment reference',
    ar: 'مرجع الطراز / المعدة',
    ur: 'ماڈل / سامان حوالہ',
    hi: 'मॉडल / उपकरण संदर्भ',
  );
  static const openingBalance = TranslatableString(
    en: 'Opening balance optional',
    ar: 'الرصيد الافتتاحي اختياري',
    ur: 'اوپننگ بیلنس اختیاری',
    hi: 'प्रारंभिक शेष वैकल्पिक',
  );
  static const openingQuantity = TranslatableString(
    en: 'Opening quantity',
    ar: 'الكمية الافتتاحية',
    ur: 'اوپننگ مقدار',
    hi: 'प्रारंभिक मात्रा',
  );
  static const openingReference = TranslatableString(
    en: 'Opening reference optional',
    ar: 'مرجع الافتتاح اختياري',
    ur: 'اوپننگ حوالہ اختیاری',
    hi: 'प्रारंभिक संदर्भ वैकल्पिक',
  );
  static const typeCategory = TranslatableString(
    en: 'Start typing a category',
    ar: 'ابدأ بكتابة الفئة',
    ur: 'کیٹیگری لکھنا شروع کریں',
    hi: 'श्रेणी लिखना शुरू करें',
  );
  static const createCategoryNamed = TranslatableString(
    en: 'Create',
    ar: 'إنشاء',
    ur: 'بنائیں',
    hi: 'बनाएं',
  );
  static const optionalParent = TranslatableString(
    en: 'Parent family optional',
    ar: 'الفئة الرئيسية اختيارية',
    ur: 'پیرنٹ فیملی اختیاری',
    hi: 'मूल परिवार वैकल्पिक',
  );
  static const selectExistingItem = TranslatableString(
    en: 'Select an inventory item',
    ar: 'اختر صنف مخزون',
    ur: 'انوینٹری آئٹم منتخب کریں',
    hi: 'इन्वेंटरी आइटम चुनें',
  );
  static const correction = TranslatableString(
    en: 'Correction',
    ar: 'تصحيح',
    ur: 'تصحیح',
    hi: 'सुधार',
  );
  static const referenceOptional = TranslatableString(
    en: 'Reference optional',
    ar: 'المرجع اختياري',
    ur: 'حوالہ اختیاری',
    hi: 'संदर्भ वैकल्पिक',
  );
  static const exportRegister = TranslatableString(
    en: 'Export register',
    ar: 'تصدير السجل',
    ur: 'رجسٹر ایکسپورٹ کریں',
    hi: 'रजिस्टर निर्यात करें',
  );
  static const exportRegisterComplete = TranslatableString(
    en: 'The current stock register was exported.',
    ar: 'تم تصدير سجل المخزون الحالي.',
    ur: 'موجودہ اسٹاک رجسٹر ایکسپورٹ ہو گیا۔',
    hi: 'मौजूदा स्टॉक रजिस्टर निर्यात हो गया।',
  );
  static const exportRegisterFailed = TranslatableString(
    en: 'The stock register could not be exported. Please try again.',
    ar: 'تعذر تصدير سجل المخزون. يرجى المحاولة مرة أخرى.',
    ur: 'اسٹاک رجسٹر ایکسپورٹ نہیں ہو سکا۔ دوبارہ کوشش کریں۔',
    hi: 'स्टॉक रजिस्टर निर्यात नहीं हो सका। फिर प्रयास करें।',
  );
  static const manageCategories = TranslatableString(
    en: 'Manage categories',
    ar: 'إدارة الفئات',
    ur: 'کیٹیگریز منظم کریں',
    hi: 'श्रेणियां प्रबंधित करें',
  );
  static const warehouseCategories = TranslatableString(
    en: 'Warehouse Categories',
    ar: 'فئات المستودع',
    ur: 'گودام کی کیٹیگریز',
    hi: 'वेयरहाउस श्रेणियां',
  );
  static const warehouseCategoriesHelp = TranslatableString(
    en: 'A shared Procurement category library. New parent categories and accepted import aliases become available to future users.',
    ar: 'مكتبة فئات مشتركة للمشتريات. تصبح الفئات الرئيسية الجديدة وأسماء الاستيراد البديلة المعتمدة متاحة للمستخدمين لاحقاً.',
    ur: 'خریداری کی مشترکہ کیٹیگری لائبریری۔ نئی بنیادی کیٹیگریز اور منظور شدہ امپورٹ عرف آئندہ صارفین کے لیے دستیاب ہوتے ہیں۔',
    hi: 'यह खरीद की साझा श्रेणी लाइब्रेरी है। नई मूल श्रेणियां और स्वीकृत आयात उपनाम भविष्य के उपयोगकर्ताओं के लिए उपलब्ध होंगे।',
  );
  static const newParentCategory = TranslatableString(
    en: 'New Parent Category',
    ar: 'فئة رئيسية جديدة',
    ur: 'نئی بنیادی کیٹیگری',
    hi: 'नई मूल श्रेणी',
  );
  static const parentCategoryHint = TranslatableString(
    en: 'e.g. Air Terminals',
    ar: 'مثال: مخارج الهواء',
    ur: 'مثلاً: ایئر ٹرمینلز',
    hi: 'जैसे: एयर टर्मिनल्स',
  );
  static const addCategory = TranslatableString(
    en: 'Add Category',
    ar: 'إضافة فئة',
    ur: 'کیٹیگری شامل کریں',
    hi: 'श्रेणी जोड़ें',
  );
  static const categoryNormalizationHelp = TranslatableString(
    en: 'Names are normalized to Title Case. The system suggests close existing categories before creating a duplicate.',
    ar: 'تُوحَّد الأسماء بصيغة العنوان. يقترح النظام الفئات المتشابهة قبل إنشاء تكرار.',
    ur: 'نام ٹائٹل کیس میں یکساں کیے جاتے ہیں۔ سسٹم نقل بنانے سے پہلے ملتی جلتی موجودہ کیٹیگریز تجویز کرتا ہے۔',
    hi: 'नाम टाइटल केस में सामान्यीकृत होते हैं। सिस्टम डुप्लिकेट बनाने से पहले समान मौजूदा श्रेणियां सुझाता है।',
  );
  static const yorksStandardCategory = TranslatableString(
    en: 'Yorks standard category',
    ar: 'فئة يوركس القياسية',
    ur: 'یارکس کی معیاری کیٹیگری',
    hi: 'यॉर्क्स मानक श्रेणी',
  );
  static const noSavedAliases = TranslatableString(
    en: 'No saved aliases yet',
    ar: 'لا توجد أسماء بديلة محفوظة بعد',
    ur: 'ابھی تک کوئی محفوظ عرف نہیں',
    hi: 'अभी तक कोई सहेजा गया उपनाम नहीं है',
  );
  static const recognizedAs = TranslatableString(
    en: 'Recognized as:',
    ar: 'يُتعرّف عليه كـ:',
    ur: 'اس نام سے پہچانا جاتا ہے:',
    hi: 'के रूप में पहचाना गया:',
  );
  static const itemsCount = TranslatableString(
    en: 'items',
    ar: 'أصناف',
    ur: 'آئٹمز',
    hi: 'आइटम',
  );
  static const importFormat = TranslatableString(
    en: 'Import Format',
    ar: 'تنسيق الاستيراد',
    ur: 'امپورٹ فارمیٹ',
    hi: 'आयात प्रारूप',
  );
  static const categoryCoverage = TranslatableString(
    en: 'Stock Catalogue by Category',
    ar: 'تغطية الفئات',
    ur: 'کیٹیگری کوریج',
    hi: 'श्रेणी कवरेज',
  );
  static const categoryCoverageHelp = TranslatableString(
    en: 'Item counts—not mixed-unit quantity totals.',
    ar: 'عدد الأصناف وليس إجمالي كميات الوحدات المختلفة.',
    ur: 'آئٹم گنتی — مختلف یونٹ مقداروں کے کل نہیں۔',
    hi: 'आइटम की संख्या—मिश्रित इकाई मात्राओं का योग नहीं।',
  );
  static const recentActivity = TranslatableString(
    en: 'Recent Stock Movements',
    ar: 'نشاط المخزون الأخير',
    ur: 'حالیہ اسٹاک سرگرمی',
    hi: 'हाल की स्टॉक गतिविधि',
  );
  static const recentActivityHelp = TranslatableString(
    en: 'Every quantity change remains attributable.',
    ar: 'يبقى كل تغيير في الكمية منسوباً إلى منفذه.',
    ur: 'ہر مقداری تبدیلی کا ذمہ دار واضح رہتا ہے۔',
    hi: 'हर मात्रा परिवर्तन का स्रोत दर्ज रहता है।',
  );
  static const search = TranslatableString(
    en: 'Search code, item, category or location',
    ar: 'ابحث بالرمز أو الصنف أو الفئة أو الموقع',
    ur: 'کوڈ، آئٹم، کیٹیگری یا مقام تلاش کریں',
    hi: 'कोड, आइटम, श्रेणी या स्थान खोजें',
  );
  static const searchInventoryItem = TranslatableString(
    en: 'Search item code or description',
    ar: 'ابحث برمز الصنف أو الوصف',
    ur: 'آئٹم کوڈ یا تفصیل تلاش کریں',
    hi: 'आइटम कोड या विवरण खोजें',
  );
  static const available = TranslatableString(
    en: 'available',
    ar: 'متاح',
    ur: 'دستیاب',
    hi: 'उपलब्ध',
  );
  static const warehouseItems = TranslatableString(
    en: 'warehouse items',
    ar: 'أصناف المستودع',
    ur: 'گودام آئٹمز',
    hi: 'वेयरहाउस आइटम',
  );
  static const warehouseItemsTitle = TranslatableString(
    en: 'Warehouse Items',
    ar: 'أصناف المستودع',
    ur: 'گودام آئٹمز',
    hi: 'वेयरहाउस आइटम',
  );
  static const warehouseItemsHelp = TranslatableString(
    en: 'On Hand and movement history are controlled; Reserved remains workflow-owned.',
    ar: 'الموجود وسجل الحركات منضبطان، بينما تظل الكمية المحجوزة مملوكة لسير العمل.',
    ur: 'آن ہینڈ اور موومنٹ ہسٹری کنٹرولڈ ہیں؛ ریزروڈ ورک فلو کے پاس رہتا ہے۔',
    hi: 'ऑन हैंड और मूवमेंट इतिहास नियंत्रित हैं; आरक्षित कार्यप्रवाह के स्वामित्व में रहता है।',
  );
  static const alias = TranslatableString(
    en: 'alias',
    ar: 'اسم بديل',
    ur: 'عرف',
    hi: 'उपनाम',
  );
  static const allStock = TranslatableString(
    en: 'All stock',
    ar: 'كل المخزون',
    ur: 'تمام اسٹاک',
    hi: 'सभी स्टॉक',
  );
  static const lowStock = TranslatableString(
    en: 'Low stock',
    ar: 'مخزون منخفض',
    ur: 'کم اسٹاک',
    hi: 'कम स्टॉक',
  );
  static const outOfStock = TranslatableString(
    en: 'Out of stock',
    ar: 'نفد المخزون',
    ur: 'اسٹاک ختم',
    hi: 'स्टॉक समाप्त',
  );
  static const healthy = TranslatableString(
    en: 'Healthy',
    ar: 'جيد',
    ur: 'صحت مند',
    hi: 'स्वस्थ',
  );
  static const uncategorized = TranslatableString(
    en: 'Uncategorized',
    ar: 'غير مصنف',
    ur: 'غیر درجہ بند',
    hi: 'अवर्गीकृत',
  );
  static const itemCode = TranslatableString(
    en: 'Item code',
    ar: 'رمز الصنف',
    ur: 'آئٹم کوڈ',
    hi: 'आइटम कोड',
  );
  static const category = TranslatableString(
    en: 'Category',
    ar: 'الفئة',
    ur: 'کیٹیگری',
    hi: 'श्रेणी',
  );
  static const location = TranslatableString(
    en: 'Location / Shelf',
    ar: 'الموقع / الرف',
    ur: 'مقام / شیلف',
    hi: 'स्थान / शेल्फ',
  );
  static const locationColumn = TranslatableString(
    en: 'Location',
    ar: 'الموقع',
    ur: 'مقام',
    hi: 'स्थान',
  );
  static const minimumStock = TranslatableString(
    en: 'Minimum stock',
    ar: 'الحد الأدنى للمخزون',
    ur: 'کم از کم اسٹاک',
    hi: 'न्यूनतम स्टॉक',
  );
  static const notes = TranslatableString(
    en: 'Notes',
    ar: 'ملاحظات',
    ur: 'نوٹس',
    hi: 'नोट्स',
  );
  static const stockQuantity = TranslatableString(
    en: 'Stock quantity',
    ar: 'كمية المخزون',
    ur: 'اسٹاک مقدار',
    hi: 'स्टॉक मात्रा',
  );
  static const newCategory = TranslatableString(
    en: 'Create as a new category',
    ar: 'إنشاء كفئة جديدة',
    ur: 'نئی کیٹیگری بنائیں',
    hi: 'नई श्रेणी बनाएं',
  );
  static const categoryName = TranslatableString(
    en: 'Category name',
    ar: 'اسم الفئة',
    ur: 'کیٹیگری نام',
    hi: 'श्रेणी नाम',
  );
  static const importTitle = TranslatableString(
    en: 'Import warehouse inventory',
    ar: 'استيراد مخزون المستودع',
    ur: 'گودام انوینٹری درآمد کریں',
    hi: 'वेयरहाउस इन्वेंटरी आयात करें',
  );
  static const importHelp = TranslatableString(
    en: 'Review every row before commit. Close matches are suggestions only; accepted wording is retained as an alias.',
    ar: 'راجع كل صف قبل الحفظ. المطابقات القريبة اقتراحات فقط، ويُحتفظ بالنص المقبول كاسم بديل.',
    ur: 'محفوظ کرنے سے پہلے ہر قطار دیکھیں۔ قریبی میچ صرف تجاویز ہیں؛ قبول شدہ عبارت بطور عرف محفوظ رہتی ہے۔',
    hi: 'कमिट से पहले हर पंक्ति देखें। निकट मिलान केवल सुझाव हैं; स्वीकृत शब्द उपनाम के रूप में सुरक्षित रहता है।',
  );
  static const selectFile = TranslatableString(
    en: 'Select Excel or CSV file',
    ar: 'اختر ملف Excel أو CSV',
    ur: 'Excel یا CSV فائل منتخب کریں',
    hi: 'Excel या CSV फ़ाइल चुनें',
  );
  static const reviewImport = TranslatableString(
    en: 'Review import',
    ar: 'مراجعة الاستيراد',
    ur: 'درآمد کا جائزہ',
    hi: 'आयात की समीक्षा',
  );
  static const commitImport = TranslatableString(
    en: 'Commit import',
    ar: 'حفظ الاستيراد',
    ur: 'درآمد محفوظ کریں',
    hi: 'आयात कमिट करें',
  );
  static const rows = TranslatableString(
    en: 'Rows',
    ar: 'الصفوف',
    ur: 'قطاریں',
    hi: 'पंक्तियां',
  );
  static const errors = TranslatableString(
    en: 'Errors',
    ar: 'الأخطاء',
    ur: 'غلطیاں',
    hi: 'त्रुटियां',
  );
  static const warnings = TranslatableString(
    en: 'Warnings',
    ar: 'التحذيرات',
    ur: 'تنبیہات',
    hi: 'चेतावनियां',
  );
  static const categoryDecision = TranslatableString(
    en: 'Choose an existing category or confirm a new one.',
    ar: 'اختر فئة موجودة أو أكد فئة جديدة.',
    ur: 'موجودہ کیٹیگری منتخب کریں یا نئی کی تصدیق کریں۔',
    hi: 'मौजूदा श्रेणी चुनें या नई की पुष्टि करें।',
  );
  static const chooseOrCreateCategory = TranslatableString(
    en: 'Choose or create',
    ar: 'اختر أو أنشئ',
    ur: 'منتخب کریں یا بنائیں',
    hi: 'चुनें या बनाएं',
  );
  static const reviewRow = TranslatableString(
    en: 'Review this row before import.',
    ar: 'راجع هذا الصف قبل الاستيراد.',
    ur: 'درآمد سے پہلے اس قطار کا جائزہ لیں۔',
    hi: 'आयात से पहले इस पंक्ति की समीक्षा करें।',
  );
  static const importSucceeded = TranslatableString(
    en: 'Inventory import committed',
    ar: 'تم حفظ استيراد المخزون',
    ur: 'انوینٹری درآمد محفوظ ہوگئی',
    hi: 'इन्वेंटरी आयात कमिट हुआ',
  );
  static const noMovements = TranslatableString(
    en: 'No stock movements yet.',
    ar: 'لا توجد حركات مخزون حتى الآن.',
    ur: 'ابھی کوئی اسٹاک موومنٹ نہیں۔',
    hi: 'अभी कोई स्टॉक मूवमेंट नहीं है।',
  );
  static const noReservations = TranslatableString(
    en: 'No active reservations.',
    ar: 'لا توجد حجوزات نشطة.',
    ur: 'کوئی فعال ریزرویشن نہیں۔',
    hi: 'कोई सक्रिय आरक्षण नहीं।',
  );
  static const request = TranslatableString(
    en: 'Request',
    ar: 'الطلب',
    ur: 'درخواست',
    hi: 'अनुरोध',
  );
  static const createdBy = TranslatableString(
    en: 'Created by',
    ar: 'أنشأها',
    ur: 'تخلیق کنندہ',
    hi: 'बनाने वाला',
  );
  static const active = TranslatableString(
    en: 'Active',
    ar: 'نشط',
    ur: 'فعال',
    hi: 'सक्रिय',
  );
  static const inactive = TranslatableString(
    en: 'Inactive',
    ar: 'غير نشط',
    ur: 'غیر فعال',
    hi: 'निष्क्रिय',
  );
  static const noItems = TranslatableString(
    en: 'No warehouse items match these filters.',
    ar: 'لا توجد أصناف تطابق عوامل التصفية.',
    ur: 'کوئی گودام آئٹم ان فلٹرز سے مطابقت نہیں رکھتا۔',
    hi: 'कोई वेयरहाउस आइटम इन फ़िल्टर से मेल नहीं खाता।',
  );
  static const savingFailed = TranslatableString(
    en: 'The server did not confirm the change. Nothing was shown as saved.',
    ar: 'لم يؤكد الخادم التغيير. لم يتم إظهار أي حفظ.',
    ur: 'سرور نے تبدیلی کی تصدیق نہیں کی۔ کچھ محفوظ نہیں دکھایا گیا۔',
    hi: 'सर्वर ने परिवर्तन की पुष्टि नहीं की। कुछ भी सहेजा हुआ नहीं दिखाया गया।',
  );
  static const activeWarehouseCatalogue = TranslatableString(
    en: 'Active warehouse catalogue',
    ar: 'كتالوج المستودع النشط',
    ur: 'فعال گودام کیٹلاگ',
    hi: 'सक्रिय वेयरहाउस कैटलॉग',
  );
  static const committedToActiveWork = TranslatableString(
    en: 'Committed to active work',
    ar: 'مخصص للعمل النشط',
    ur: 'فعال کام کے لیے مختص',
    hi: 'सक्रिय कार्य के लिए प्रतिबद्ध',
  );
  static const configuredThresholds = TranslatableString(
    en: 'Configured thresholds',
    ar: 'الحدود المهيأة',
    ur: 'ترتیب شدہ حدیں',
    hi: 'कॉन्फ़िगर की गई सीमाएँ',
  );
  static const noAvailableQuantity = TranslatableString(
    en: 'No available quantity',
    ar: 'لا توجد كمية متاحة',
    ur: 'کوئی دستیاب مقدار نہیں',
    hi: 'कोई उपलब्ध मात्रा नहीं',
  );
  static const onlyAttentionItems = TranslatableString(
    en: 'Only stock conditions requiring a decision are shown.',
    ar: 'تظهر فقط حالات المخزون التي تتطلب قراراً.',
    ur: 'صرف فیصلہ درکار اسٹاک حالات دکھائے جاتے ہیں۔',
    hi: 'केवल निर्णय की आवश्यकता वाली स्टॉक स्थितियां दिखाई जाती हैं।',
  );
  static const commonProcurementActions = TranslatableString(
    en: 'Common Procurement actions.',
    ar: 'إجراءات المشتريات الشائعة.',
    ur: 'عام پروکیورمنٹ اقدامات۔',
    hi: 'सामान्य खरीद क्रियाएं।',
  );
  static const controlledExcelStructure = TranslatableString(
    en: 'Controlled Excel structure',
    ar: 'بنية Excel مضبوطة',
    ur: 'کنٹرول شدہ ایکسل ڈھانچہ',
    hi: 'नियंत्रित एक्सेल संरचना',
  );
  static const previewBeforeCommit = TranslatableString(
    en: 'Preview before commit',
    ar: 'معاينة قبل الحفظ',
    ur: 'محفوظ کرنے سے پہلے پیش منظر',
    hi: 'कमिट से पहले पूर्वावलोकन',
  );
  static const movementNotBalanceOverwrite = TranslatableString(
    en: 'Movement, not balance overwrite',
    ar: 'حركة وليست استبدال رصيد',
    ur: 'موومنٹ، بیلنس اووررائٹ نہیں',
    hi: 'मूवमेंट, बैलेंस ओवरराइट नहीं',
  );
  static const currentOperationalSnapshot = TranslatableString(
    en: 'Current operational snapshot',
    ar: 'لقطة تشغيلية حالية',
    ur: 'موجودہ آپریشنل منظر',
    hi: 'वर्तमान परिचालन स्नैपशॉट',
  );
  static const reusableSmartCategoryLibrary = TranslatableString(
    en: 'Reusable smart category library',
    ar: 'مكتبة فئات ذكية قابلة لإعادة الاستخدام',
    ur: 'دوبارہ استعمال ہونے والی سمارٹ کیٹیگری لائبریری',
    hi: 'पुन: उपयोग योग्य स्मार्ट श्रेणी लाइब्रेरी',
  );
  static const searchWarehouse = TranslatableString(
    en: 'Search warehouse',
    ar: 'بحث في المستودع',
    ur: 'گودام تلاش کریں',
    hi: 'वेयरहाउस खोजें',
  );
  static const itemSearchHint = TranslatableString(
    en: 'Item code, description, make, unit or location',
    ar: 'رمز الصنف أو الوصف أو المنشأ أو الوحدة أو الموقع',
    ur: 'آئٹم کوڈ، تفصیل، برانڈ، یونٹ یا مقام',
    hi: 'आइटम कोड, विवरण, ब्रांड, यूनिट या स्थान',
  );
  static const status = TranslatableString(
    en: 'Status',
    ar: 'الحالة',
    ur: 'حالت',
    hi: 'स्थिति',
  );
  static const allStatus = TranslatableString(
    en: 'All Status',
    ar: 'كل الحالات',
    ur: 'تمام حالتیں',
    hi: 'सभी स्थितियां',
  );
  static const allUnits = TranslatableString(
    en: 'All Units',
    ar: 'كل الوحدات',
    ur: 'تمام یونٹس',
    hi: 'सभी यूनिट',
  );
  static const allCategories = TranslatableString(
    en: 'All Categories',
    ar: 'كل الفئات',
    ur: 'تمام کیٹیگریز',
    hi: 'सभी श्रेणियां',
  );
  static const inStock = TranslatableString(
    en: 'In Stock',
    ar: 'متوفر',
    ur: 'اسٹاک میں',
    hi: 'स्टॉक में',
  );
  static const stock = TranslatableString(
    en: 'Stock',
    ar: 'مخزون',
    ur: 'اسٹاک',
    hi: 'स्टॉक',
  );
  static const view = TranslatableString(
    en: 'View',
    ar: 'عرض',
    ur: 'دیکھیں',
    hi: 'देखें',
  );
  static const stockMovements = TranslatableString(
    en: 'Stock Movement History',
    ar: 'سجل حركات المخزون',
    ur: 'اسٹاک موومنٹ کی تاریخ',
    hi: 'स्टॉक मूवमेंट इतिहास',
  );
  static const movementHistoryHelp = TranslatableString(
    en: 'Quantity delta, balance after, actor, reason and source reference remain visible.',
    ar: 'يبقى فرق الكمية والرصيد والمنفذ والسبب والمرجع ظاهراً.',
    ur: 'مقدار فرق، بعد کا بیلنس، عامل، وجہ اور حوالہ نظر آتے رہتے ہیں۔',
    hi: 'मात्रा अंतर, बाद का बैलेंस, कर्ता, कारण और स्रोत संदर्भ दिखते रहते हैं।',
  );
  static const immutableHistory = TranslatableString(
    en: 'Immutable history',
    ar: 'سجل غير قابل للتغيير',
    ur: 'ناقابل تبدیلی تاریخ',
    hi: 'अपरिवर्तनीय इतिहास',
  );
  static const searchMovements = TranslatableString(
    en: 'Search movements',
    ar: 'بحث في الحركات',
    ur: 'موومنٹس تلاش کریں',
    hi: 'मूवमेंट खोजें',
  );
  static const movementSearchHint = TranslatableString(
    en: 'Item, reference, reason or actor',
    ar: 'الصنف أو المرجع أو السبب أو المنفذ',
    ur: 'آئٹم، حوالہ، وجہ یا عامل',
    hi: 'आइटम, संदर्भ, कारण या कर्ता',
  );
  static const movementType = TranslatableString(
    en: 'Movement Type',
    ar: 'نوع الحركة',
    ur: 'موومنٹ کی قسم',
    hi: 'मूवमेंट प्रकार',
  );
  static const allMovements = TranslatableString(
    en: 'All Movements',
    ar: 'كل الحركات',
    ur: 'تمام موومنٹس',
    hi: 'सभी मूवमेंट',
  );
  static const stockIn = TranslatableString(
    en: 'Stock In',
    ar: 'إدخال مخزون',
    ur: 'اسٹاک اِن',
    hi: 'स्टॉक इन',
  );
  static const stockOut = TranslatableString(
    en: 'Stock Out',
    ar: 'إخراج مخزون',
    ur: 'اسٹاک آؤٹ',
    hi: 'स्टॉक आउट',
  );
  static const warehouseDispatch = TranslatableString(
    en: 'Warehouse Dispatch',
    ar: 'إرسال المستودع',
    ur: 'گودام ڈسپیچ',
    hi: 'वेयरहाउस डिस्पैच',
  );
  static const materialReturn = TranslatableString(
    en: 'Material Return',
    ar: 'إرجاع مواد',
    ur: 'مواد واپسی',
    hi: 'सामग्री वापसी',
  );
  static const activeReservations = TranslatableString(
    en: 'Active Reservations',
    ar: 'الحجوزات النشطة',
    ur: 'فعال ریزرویشنز',
    hi: 'सक्रिय आरक्षण',
  );
  static const reservationsHelp = TranslatableString(
    en: 'Read-only commitments created by approved warehouse-sourced Material Requests.',
    ar: 'التزامات للقراءة فقط أنشأتها طلبات المواد المعتمدة من المستودع.',
    ur: 'منظور شدہ گودام سے ماخذ مواد کی درخواستوں کی صرف پڑھنے کی پابندیاں۔',
    hi: 'स्वीकृत वेयरहाउस-स्रोत सामग्री अनुरोधों द्वारा बनाई गई केवल-पढ़ने योग्य प्रतिबद्धताएं।',
  );
  static const materialRequest = TranslatableString(
    en: 'Material Request',
    ar: 'طلب مواد',
    ur: 'مواد کی درخواست',
    hi: 'सामग्री अनुरोध',
  );
  static const projectScope = TranslatableString(
    en: 'Project / Scope',
    ar: 'المشروع / النطاق',
    ur: 'پراجیکٹ / اسکوپ',
    hi: 'प्रोजेक्ट / स्कोप',
  );
  static const inventoryItem = TranslatableString(
    en: 'Inventory Item',
    ar: 'صنف المخزون',
    ur: 'انوینٹری آئٹم',
    hi: 'इन्वेंटरी आइटम',
  );
  static const openMaterialRequest = TranslatableString(
    en: 'Open MR',
    ar: 'فتح طلب المواد',
    ur: 'مواد کی درخواست کھولیں',
    hi: 'सामग्री अनुरोध खोलें',
  );
  static const previewInventoryImport = TranslatableString(
    en: 'Preview Inventory Import',
    ar: 'معاينة استيراد المخزون',
    ur: 'انوینٹری درآمد کا پیش منظر',
    hi: 'इन्वेंटरी इम्पोर्ट पूर्वावलोकन',
  );
  static const nothingChangesUntilConfirm = TranslatableString(
    en: 'Nothing changes until Confirm Import',
    ar: 'لا يتغير شيء قبل تأكيد الاستيراد',
    ur: 'درآمد کی تصدیق تک کچھ تبدیل نہیں ہوتا',
    hi: 'इम्पोर्ट की पुष्टि तक कुछ नहीं बदलता',
  );
  static const rowsFound = TranslatableString(
    en: 'Rows Found',
    ar: 'الصفوف الموجودة',
    ur: 'ملنے والی قطاریں',
    hi: 'पंक्तियां मिलीं',
  );
  static const nonEmptyDataRows = TranslatableString(
    en: 'Non-empty data rows',
    ar: 'صفوف بيانات غير فارغة',
    ur: 'خالی نہ ہونے والی ڈیٹا قطاریں',
    hi: 'गैर-रिक्त डेटा पंक्तियां',
  );
  static const newItems = TranslatableString(
    en: 'New Items',
    ar: 'أصناف جديدة',
    ur: 'نئے آئٹمز',
    hi: 'नई आइटम',
  );
  static const willCreateItemMasters = TranslatableString(
    en: 'Will create item masters',
    ar: 'سيتم إنشاء سجلات الأصناف',
    ur: 'آئٹم ماسٹر بنائے جائیں گے',
    hi: 'आइटम मास्टर बनाए जाएंगे',
  );
  static const existingMatches = TranslatableString(
    en: 'Existing Matches',
    ar: 'مطابقات موجودة',
    ur: 'موجودہ مماثلتیں',
    hi: 'मौजूदा मिलान',
  );
  static const matchedByCodeOrIdentity = TranslatableString(
    en: 'Matched by code or identity',
    ar: 'مطابقة بالرمز أو الهوية',
    ur: 'کوڈ یا شناخت سے مماثل',
    hi: 'कोड या पहचान से मिलान',
  );
  static const needReview = TranslatableString(
    en: 'Need Review',
    ar: 'تحتاج مراجعة',
    ur: 'جائزہ درکار',
    hi: 'समीक्षा जरूरी',
  );
  static const readyWithWarnings = TranslatableString(
    en: 'Ready with warnings',
    ar: 'جاهز مع تحذيرات',
    ur: 'تنبیہات کے ساتھ تیار',
    hi: 'चेतावनियों के साथ तैयार',
  );
  static const smartCategoryMappingActive = TranslatableString(
    en: 'Smart category mapping is active',
    ar: 'تعيين الفئات الذكي نشط',
    ur: 'سمارٹ کیٹیگری میپنگ فعال ہے',
    hi: 'स्मार्ट श्रेणी मैपिंग सक्रिय है',
  );
  static const smartCategoryMappingHelp = TranslatableString(
    en: 'Existing category names and saved aliases are reused. Close matches require your decision. New categories are created only after Confirm Import.',
    ar: 'يعاد استخدام أسماء الفئات والأسماء البديلة المحفوظة. تتطلب المطابقات القريبة قرارك. لا تُنشأ الفئات الجديدة إلا بعد التأكيد.',
    ur: 'موجودہ کیٹیگری نام اور محفوظ عرف دوبارہ استعمال ہوتے ہیں۔ قریبی مماثلت آپ کا فیصلہ مانگتی ہے۔ نئی کیٹیگری صرف تصدیق کے بعد بنتی ہے۔',
    hi: 'मौजूदा श्रेणी नाम और सहेजे गए उपनाम फिर से उपयोग होते हैं। निकट मिलान के लिए आपका निर्णय जरूरी है। नई श्रेणियां केवल पुष्टि के बाद बनती हैं।',
  );
  static const reviewWarningsBeforeImport = TranslatableString(
    en: 'Review warnings before import',
    ar: 'راجع التحذيرات قبل الاستيراد',
    ur: 'درآمد سے پہلے وارننگز کا جائزہ لیں',
    hi: 'इम्पोर्ट से पहले चेतावनियों की समीक्षा करें',
  );
  static const serverRevalidatesBeforeCommit = TranslatableString(
    en: 'The server revalidates the same rules before commit.',
    ar: 'يعيد الخادم التحقق من القواعد نفسها قبل الحفظ.',
    ur: 'سرور محفوظ کرنے سے پہلے انہی قواعد کی دوبارہ توثیق کرتا ہے۔',
    hi: 'सर्वर कमिट से पहले इन्हीं नियमों का पुनः सत्यापन करता है।',
  );
  static const row = TranslatableString(
    en: 'Row',
    ar: 'الصف',
    ur: 'قطار',
    hi: 'पंक्ति',
  );
  static const stockAction = TranslatableString(
    en: 'Stock Action',
    ar: 'إجراء المخزون',
    ur: 'اسٹاک ایکشن',
    hi: 'स्टॉक कार्रवाई',
  );
  static const itemMatchResult = TranslatableString(
    en: 'Item Match / Result',
    ar: 'مطابقة / نتيجة الصنف',
    ur: 'آئٹم مماثلت / نتیجہ',
    hi: 'आइटम मिलान / परिणाम',
  );
  static const validation = TranslatableString(
    en: 'Validation',
    ar: 'التحقق',
    ur: 'توثیق',
    hi: 'सत्यापन',
  );
  static const chooseAnotherFile = TranslatableString(
    en: 'Choose Another File',
    ar: 'اختر ملفاً آخر',
    ur: 'دوسری فائل منتخب کریں',
    hi: 'दूसरी फ़ाइल चुनें',
  );
  static const confirmImport = TranslatableString(
    en: 'Confirm Import',
    ar: 'تأكيد الاستيراد',
    ur: 'درآمد کی تصدیق کریں',
    hi: 'इम्पोर्ट की पुष्टि करें',
  );
  static const ready = TranslatableString(
    en: 'Ready',
    ar: 'جاهز',
    ur: 'تیار',
    hi: 'तैयार',
  );
}
