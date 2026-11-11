import 'app_strings.dart';
import 'yorks_v1_arrangement.dart';

/// Centralized user-facing copy for the Batch 6 arrangement workflow.
abstract final class YorksV1ArrangementStrings {
  static const quantityNeeded = TranslatableString(
    en: 'Enter quantity',
    ar: 'أدخل الكمية',
    ur: 'مقدار درج کریں',
    hi: 'मात्रा दर्ज करें',
  );
  static const shelfLocation = TranslatableString(
    en: 'Shelf / bin',
    ar: 'الرف / الموقع',
    ur: 'شیلف / خانہ',
    hi: 'शेल्फ / बिन',
  );
  static const shelfLocationMissing = TranslatableString(
    en: 'Shelf / bin not set',
    ar: 'لم يتم تحديد الرف / الموقع',
    ur: 'شیلف / خانہ درج نہیں ہے',
    hi: 'शेल्फ / बिन दर्ज नहीं है',
  );
  static const searchItems = TranslatableString(
    en: 'Search items',
    ar: 'بحث عن المواد',
    ur: 'اشیاء تلاش کریں',
    hi: 'आइटम खोजें',
  );
  static const allItems = TranslatableString(
    en: 'All items',
    ar: 'كل المواد',
    ur: 'تمام اشیاء',
    hi: 'सभी आइटम',
  );
  static const reviewArrangement = TranslatableString(
    en: 'Review arrangement',
    ar: 'مراجعة الترتيب',
    ur: 'انتظام کا جائزہ',
    hi: 'व्यवस्था की समीक्षा',
  );
  static const reviewBeforeSave = TranslatableString(
    en: 'Check quantities and sources. Saving commits this arrangement and reserves warehouse stock.',
    ar: 'تحقق من الكميات والمصادر. يؤدي الحفظ إلى اعتماد هذا الترتيب وحجز مخزون المستودع.',
    ur: 'مقدار اور ذرائع چیک کریں۔ محفوظ کرنے سے انتظام اور گودام اسٹاک کا ریزرویشن مکمل ہوگا۔',
    hi: 'मात्राएँ और स्रोत जाँचें। सहेजने से व्यवस्था पूरी होगी और गोदाम स्टॉक आरक्षित होगा।',
  );
  static const noMatchingWarehouse = TranslatableString(
    en: 'No matching items',
    ar: 'لا توجد مواد مطابقة',
    ur: 'کوئی متعلقہ آئٹم نہیں',
    hi: 'कोई मिलान नहीं',
  );

  static const arrangement = TranslatableString(
    en: 'Procurement arrangement',
    ar: 'ترتيب المشتريات',
    ur: 'پروکیورمنٹ انتظام',
    hi: 'खरीद व्यवस्था',
  );
  static const arrangeMaterialRequest = TranslatableString(
    en: 'Arrange Material Request',
    ar: 'ترتيب طلب المواد',
    ur: 'مواد کی درخواست ترتیب دیں',
    hi: 'सामग्री अनुरोध व्यवस्थित करें',
  );
  static const arrangeMaterialRequestDescription = TranslatableString(
    en: 'Supply available lines or clearly mark what cannot be provided.',
    ar: 'وفّر البنود المتاحة أو وضّح بوضوح ما لا يمكن توفيره.',
    ur: 'دستیاب لائنیں فراہم کریں یا واضح طور پر نشان زد کریں جو فراہم نہیں ہو سکتیں۔',
    hi: 'उपलब्ध पंक्तियों की आपूर्ति करें या स्पष्ट रूप से चिह्नित करें कि क्या उपलब्ध नहीं कराया जा सकता।',
  );
  static const arrangeRequestedItems = TranslatableString(
    en: 'Arrange requested items',
    ar: 'ترتيب المواد المطلوبة',
    ur: 'درخواست کردہ اشیاء ترتیب دیں',
    hi: 'अनुरोधित सामग्री व्यवस्थित करें',
  );
  static const decideEveryLine = TranslatableString(
    en: 'Requested quantities are filled in. Adjust any quantity you cannot provide in full.',
    ar: 'تمت تعبئة الكميات المطلوبة. عدّل أي كمية لا يمكنك توفيرها بالكامل.',
    ur: 'مطلوبہ مقداریں درج ہیں۔ جو مقدار مکمل فراہم نہیں کر سکتے اسے تبدیل کریں۔',
    hi: 'माँगी गई मात्राएँ भरी हैं। जो मात्रा पूरी नहीं दे सकते उसे बदलें।',
  );
  static const arrangeItem = TranslatableString(
    en: 'Arrange Item',
    ar: 'ترتيب البند',
    ur: 'آئٹم ترتیب دیں',
    hi: 'वस्तु व्यवस्थित करें',
  );
  static const available = TranslatableString(
    en: 'Available',
    ar: 'المتاح',
    ur: 'دستیاب',
    hi: 'उपलब्ध',
  );
  static const previous = TranslatableString(
    en: 'Previous',
    ar: 'السابق',
    ur: 'پچھلا',
    hi: 'पिछला',
  );
  static const saveAndNext = TranslatableString(
    en: 'Next item',
    ar: 'البند التالي',
    ur: 'اگلی شے',
    hi: 'अगला आइटम',
  );
  static const arrangementReview = TranslatableString(
    en: 'Arrangement Summary',
    ar: 'ملخص الترتيب',
    ur: 'انتظام کا خلاصہ',
    hi: 'व्यवस्था सारांश',
  );
  static const readyForProjectEngineer = TranslatableString(
    en: 'Ready for delivery',
    ar: 'جاهز للتسليم',
    ur: 'ڈیلیوری کے لیے تیار',
    hi: 'डिलीवरी के लिए तैयार',
  );
  static const approvalReleasesArranged = TranslatableString(
    en: 'Saving makes only the arranged quantities available for controlled dispatch.',
    ar: 'يجعل الحفظ الكميات المرتبة فقط متاحة للإرسال المتحكم به.',
    ur: 'محفوظ کرنے سے صرف ترتیب شدہ مقدار کنٹرولڈ ڈسپیچ کے لیے دستیاب ہوتی ہے۔',
    hi: 'सहेजने से केवल व्यवस्थित मात्रा नियंत्रित डिस्पैच के लिए उपलब्ध होती है।',
  );
  static const projectEngineerReview = TranslatableString(
    en: 'Project Engineer Review',
    ar: 'مراجعة مهندس المشروع',
    ur: 'پروجیکٹ انجینئر کا جائزہ',
    hi: 'प्रोजेक्ट इंजीनियर समीक्षा',
  );
  static const reviewExceptionsFirst = TranslatableString(
    en: 'Review exceptions first, then approve or return the full arrangement.',
    ar: 'راجع الاستثناءات أولاً ثم اعتمد الترتيب كاملاً أو أعده.',
    ur: 'پہلے استثنائی لائنوں کا جائزہ لیں، پھر مکمل انتظام منظور یا واپس کریں۔',
    hi: 'पहले अपवादों की समीक्षा करें, फिर पूरी व्यवस्था मंजूर या वापस करें।',
  );
  static const allMaterialLines = TranslatableString(
    en: 'All material lines',
    ar: 'جميع بنود المواد',
    ur: 'تمام میٹریل لائنز',
    hi: 'सभी सामग्री पंक्तियाँ',
  );
  static const materialLineFacts = TranslatableString(
    en: 'Requested, arranged, source and reason',
    ar: 'المطلوب والمرتب والمصدر والسبب',
    ur: 'درخواست، ترتیب، ذریعہ اور وجہ',
    hi: 'अनुरोधित, व्यवस्थित, स्रोत और कारण',
  );
  static const approvalMeaning = TranslatableString(
    en: 'What approval means',
    ar: 'ماذا تعني الموافقة',
    ur: 'منظوری کا مطلب',
    hi: 'मंजूरी का अर्थ',
  );
  static const approvalMeaningMessage = TranslatableString(
    en: 'Only positive arranged quantities become dispatchable. Unavailable lines remain in history.',
    ar: 'تصبح الكميات المرتبة الموجبة فقط قابلة للإرسال، وتبقى البنود غير المتاحة في السجل.',
    ur: 'صرف مثبت ترتیب شدہ مقدار ڈسپیچ ہو سکتی ہے۔ غیر دستیاب لائنز تاریخ میں رہتی ہیں۔',
    hi: 'केवल सकारात्मक व्यवस्थित मात्राएँ भेजी जा सकती हैं। अनुपलब्ध पंक्तियाँ इतिहास में रहती हैं।',
  );
  static const returnArrangement = TranslatableString(
    en: 'Return Arrangement',
    ar: 'إعادة الترتيب',
    ur: 'انتظام واپس کریں',
    hi: 'व्यवस्था लौटाएँ',
  );
  static const whatNeedsToChange = TranslatableString(
    en: 'What needs to change?',
    ar: 'ما الذي يحتاج إلى تغيير؟',
    ur: 'کیا تبدیل کرنا ضروری ہے؟',
    hi: 'क्या बदलना चाहिए?',
  );
  static const returnReasonRecorded = TranslatableString(
    en: 'Your reason is recorded and the next arrangement version will be prefilled.',
    ar: 'سيتم تسجيل سببك وتعبئة إصدار الترتيب التالي مسبقاً.',
    ur: 'آپ کی وجہ محفوظ ہوگی اور انتظام کا اگلا ورژن پہلے سے بھرا ہوگا۔',
    hi: 'आपका कारण दर्ज होगा और अगला व्यवस्था संस्करण पहले से भरा होगा।',
  );
  static const returnReasonHint = TranslatableString(
    en: 'Required and visible to Procurement.',
    ar: 'مطلوب ومرئي للمشتريات.',
    ur: 'ضروری اور پروکیورمنٹ کو نظر آتا ہے۔',
    hi: 'आवश्यक और खरीद विभाग को दिखाई देता है।',
  );
  static const dateFormatHint = TranslatableString(
    en: 'YYYY-MM-DD',
    ar: 'YYYY-MM-DD',
    ur: 'YYYY-MM-DD',
    hi: 'YYYY-MM-DD',
  );
  static const whatHappensNext = TranslatableString(
    en: 'What happens next',
    ar: 'ما الذي يحدث بعد ذلك',
    ur: 'اگلا مرحلہ',
    hi: 'आगे क्या होगा',
  );
  static const returnedArrangementHistory = TranslatableString(
    en: 'Procurement receives a new editable arrangement version. The current version remains immutable in history.',
    ar: 'تستلم المشتريات إصداراً جديداً قابلاً للتعديل، ويبقى الإصدار الحالي ثابتاً في السجل.',
    ur: 'پروکیورمنٹ کو نیا قابل ترمیم ورژن ملے گا۔ موجودہ ورژن تاریخ میں ناقابل تبدیلی رہے گا۔',
    hi: 'खरीद विभाग को नया संपादन योग्य संस्करण मिलेगा। वर्तमान संस्करण इतिहास में अपरिवर्तनीय रहेगा।',
  );
  static const quantityRule = TranslatableString(
    en: 'Arranged quantity can never exceed the requested quantity. Warehouse quantities are also checked against current available inventory.',
    ar: 'لا يمكن أن تتجاوز الكمية المرتبة الكمية المطلوبة. كما يتم التحقق من كميات المستودع مقابل المخزون المتاح الحالي.',
    ur: 'ترتیب شدہ مقدار کبھی مطلوبہ مقدار سے زیادہ نہیں ہو سکتی۔ گودام کی مقدار بھی موجودہ دستیاب انوینٹری کے خلاف چیک ہوتی ہے۔',
    hi: 'व्यवस्थित मात्रा अनुरोधित मात्रा से अधिक नहीं हो सकती। गोदाम की मात्राओं की वर्तमान उपलब्ध इन्वेंटरी से भी जांच होती है।',
  );
  static const arrangementHistory = TranslatableString(
    en: 'Arrangement history',
    ar: 'سجل الترتيبات',
    ur: 'انتظام کی تاریخ',
    hi: 'व्यवस्था इतिहास',
  );
  static const startArrangement = TranslatableString(
    en: 'Start arrangement',
    ar: 'بدء الترتيب',
    ur: 'انتظام شروع کریں',
    hi: 'व्यवस्था शुरू करें',
  );
  static const saveForApproval = TranslatableString(
    en: 'Save arrangement',
    ar: 'حفظ الترتيب',
    ur: 'انتظام محفوظ کریں',
    hi: 'व्यवस्था सहेजें',
  );
  static const approveArrangement = TranslatableString(
    en: 'Approve arrangement',
    ar: 'اعتماد الترتيب',
    ur: 'انتظام منظور کریں',
    hi: 'व्यवस्था स्वीकृत करें',
  );
  static const reviewAndApprove = TranslatableString(
    en: 'Review & Approve',
    ar: 'مراجعة واعتماد',
    ur: 'جائزہ لیں اور منظور کریں',
    hi: 'समीक्षा करें और स्वीकृत करें',
  );
  static const returnToProcurement = TranslatableString(
    en: 'Return to Procurement',
    ar: 'إعادة إلى المشتريات',
    ur: 'پروکیورمنٹ کو واپس بھیجیں',
    hi: 'खरीद विभाग को लौटाएँ',
  );
  static const returnAction = TranslatableString(
    en: 'Return',
    ar: 'إرجاع',
    ur: 'واپس کریں',
    hi: 'लौटाएँ',
  );
  static const approveAction = TranslatableString(
    en: 'Approve',
    ar: 'اعتماد',
    ur: 'منظور کریں',
    hi: 'स्वीकृत करें',
  );
  static const returnReason = TranslatableString(
    en: 'Return reason',
    ar: 'سبب الإرجاع',
    ur: 'واپسی کی وجہ',
    hi: 'वापसी का कारण',
  );
  static const requested = TranslatableString(
    en: 'Requested',
    ar: 'المطلوب',
    ur: 'درخواست کردہ',
    hi: 'अनुरोधित',
  );
  static const requestedItem = TranslatableString(
    en: 'Requested item',
    ar: 'البند المطلوب',
    ur: 'درخواست کردہ آئٹم',
    hi: 'अनुरोधित आइटम',
  );
  static const clarifyItem = TranslatableString(
    en: 'Edit item details',
    ar: 'تعديل تفاصيل البند',
    ur: 'آئٹم کی تفصیل میں ترمیم کریں',
    hi: 'वस्तु विवरण संपादित करें',
  );
  static const clarifyItemDescription = TranslatableString(
    en: 'Edit the Procurement item name or model before arranging it. The original request stays in history and Engineering must approve the change.',
    ar: 'عدّل اسم بند المشتريات أو طرازه قبل ترتيبه. يبقى الطلب الأصلي في السجل ويجب أن تعتمد الهندسة التغيير.',
    ur: 'انتظام سے پہلے پروکیورمنٹ آئٹم کا نام یا ماڈل تبدیل کریں۔ اصل درخواست تاریخ میں محفوظ رہے گی اور تبدیلی کے لیے انجینئرنگ کی منظوری ضروری ہے۔',
    hi: 'व्यवस्था से पहले खरीद वस्तु का नाम या मॉडल संपादित करें। मूल अनुरोध इतिहास में रहेगा और बदलाव के लिए इंजीनियरिंग की स्वीकृति आवश्यक है।',
  );
  static const effectiveItem = TranslatableString(
    en: 'Procurement item',
    ar: 'بند المشتريات',
    ur: 'پروکیورمنٹ آئٹم',
    hi: 'खरीद वस्तु',
  );
  static const itemName = TranslatableString(
    en: 'Item name',
    ar: 'اسم البند',
    ur: 'آئٹم کا نام',
    hi: 'वस्तु का नाम',
  );
  static const modelReference = TranslatableString(
    en: 'Model number',
    ar: 'رقم الطراز',
    ur: 'ماڈل نمبر',
    hi: 'मॉडल नंबर',
  );
  static const modelReferenceOptional = TranslatableString(
    en: 'Model number optional',
    ar: 'رقم الطراز اختياري',
    ur: 'ماڈل نمبر اختیاری',
    hi: 'मॉडल नंबर वैकल्पिक',
  );
  static const searchKnownItems = TranslatableString(
    en: 'Search project BOQ and inventory',
    ar: 'البحث في جدول كميات المشروع والمخزون',
    ur: 'پروجیکٹ BOQ اور انوینٹری تلاش کریں',
    hi: 'प्रोजेक्ट BOQ और इन्वेंटरी खोजें',
  );
  static const searchKnownItemsHint = TranslatableString(
    en: 'Type an item name, model, brand or code',
    ar: 'اكتب اسم البند أو الطراز أو العلامة أو الرمز',
    ur: 'آئٹم کا نام، ماڈل، برانڈ یا کوڈ لکھیں',
    hi: 'वस्तु का नाम, मॉडल, ब्रांड या कोड लिखें',
  );
  static const keepEnteredItem = TranslatableString(
    en: 'Keep entered details',
    ar: 'الاحتفاظ بالتفاصيل المدخلة',
    ur: 'درج تفصیل برقرار رکھیں',
    hi: 'दर्ज विवरण रखें',
  );
  static const noMatchingItems = TranslatableString(
    en: 'No matching BOQ or inventory item. You can keep the entered details.',
    ar: 'لا يوجد بند مطابق في جدول الكميات أو المخزون. يمكنك الاحتفاظ بالتفاصيل المدخلة.',
    ur: 'BOQ یا انوینٹری میں کوئی مماثل آئٹم نہیں۔ آپ درج تفصیل برقرار رکھ سکتے ہیں۔',
    hi: 'BOQ या इन्वेंटरी में कोई मेल नहीं मिला। आप दर्ज विवरण रख सकते हैं।',
  );
  static const originallyRequested = TranslatableString(
    en: 'Originally requested',
    ar: 'الطلب الأصلي',
    ur: 'اصل درخواست',
    hi: 'मूल अनुरोध',
  );
  static const clarificationEvidenceHelp = TranslatableString(
    en: 'The original request stays in history. This clarification is used for arrangement and delivery records.',
    ar: 'يبقى الطلب الأصلي في السجل. ويُستخدم هذا التوضيح في الترتيب وسجلات التسليم.',
    ur: 'اصل درخواست تاریخ میں محفوظ رہتی ہے۔ یہ وضاحت انتظام اور ڈیلیوری ریکارڈ میں استعمال ہوگی۔',
    hi: 'मूल अनुरोध इतिहास में रहता है। यह स्पष्टीकरण व्यवस्था और डिलीवरी रिकॉर्ड में उपयोग होगा।',
  );
  static const saveClarification = TranslatableString(
    en: 'Save item details',
    ar: 'حفظ تفاصيل البند',
    ur: 'آئٹم کی تفصیل محفوظ کریں',
    hi: 'वस्तु विवरण सहेजें',
  );
  static const clarificationSaved = TranslatableString(
    en: 'Sent for Engineering approval',
    ar: 'تم الإرسال لموافقة الهندسة',
    ur: 'انجینئرنگ کی منظوری کے لیے بھیج دیا گیا',
    hi: 'इंजीनियरिंग स्वीकृति के लिए भेजा गया',
  );
  static const clarificationSavedMessage = TranslatableString(
    en: 'The corrected item details are saved. Arrangement will unlock after the Project Engineer approves them.',
    ar: 'تم حفظ تفاصيل البند المصححة. سيُفتح الترتيب بعد موافقة مهندس المشروع عليها.',
    ur: 'درست شدہ آئٹم کی تفصیل محفوظ ہے۔ پروجیکٹ انجینئر کی منظوری کے بعد انتظام دوبارہ کھلے گا۔',
    hi: 'सुधारा गया वस्तु विवरण सहेजा गया है। प्रोजेक्ट इंजीनियर की स्वीकृति के बाद व्यवस्था फिर खुलेगी।',
  );
  static const clarificationReviewTitle = TranslatableString(
    en: 'Engineering approval required',
    ar: 'موافقة الهندسة مطلوبة',
    ur: 'انجینئرنگ کی منظوری درکار ہے',
    hi: 'इंजीनियरिंग स्वीकृति आवश्यक है',
  );
  static const clarificationReviewMessage = TranslatableString(
    en: 'Procurement corrected the item name or model. Arrangement details are read-only until the Project Engineer approves the latest correction.',
    ar: 'صححت المشتريات اسم البند أو الطراز. تظل تفاصيل الترتيب للقراءة فقط حتى يوافق مهندس المشروع على أحدث تصحيح.',
    ur: 'پروکیورمنٹ نے آئٹم کا نام یا ماڈل درست کیا ہے۔ تازہ ترین تصحیح پر پروجیکٹ انجینئر کی منظوری تک انتظام کی تفصیل صرف پڑھی جا سکتی ہے۔',
    hi: 'प्रोक्योरमेंट ने वस्तु का नाम या मॉडल सुधारा है। नवीनतम सुधार को प्रोजेक्ट इंजीनियर की स्वीकृति मिलने तक व्यवस्था विवरण केवल पढ़ने योग्य हैं।',
  );
  static const clarificationLocked = TranslatableString(
    en: 'Item details are locked after the arrangement is saved.',
    ar: 'تُقفل تفاصيل البند بعد حفظ الترتيب.',
    ur: 'انتظام محفوظ ہونے کے بعد آئٹم کی تفصیل مقفل ہے۔',
    hi: 'व्यवस्था सहेजने के बाद वस्तु विवरण लॉक हो जाता है।',
  );
  static const clarificationFailed = TranslatableString(
    en: 'Item details could not be updated. Refresh and review the current arrangement.',
    ar: 'تعذر تحديث تفاصيل البند. حدّث الصفحة وراجع الترتيب الحالي.',
    ur: 'آئٹم کی تفصیل اپ ڈیٹ نہیں ہو سکی۔ ریفریش کرکے موجودہ انتظام دیکھیں۔',
    hi: 'वस्तु विवरण अपडेट नहीं हुआ। रीफ़्रेश करके वर्तमान व्यवस्था देखें।',
  );
  static const boqCorrelation = TranslatableString(
    en: 'Linked to BOQ',
    ar: 'مرتبط بجدول الكميات',
    ur: 'BOQ سے منسلک',
    hi: 'बीओक्यू से जुड़ा',
  );
  static const customRequestItem = TranslatableString(
    en: 'Custom request item',
    ar: 'بند طلب مخصص',
    ur: 'کسٹم درخواست آئٹم',
    hi: 'कस्टम अनुरोध आइटम',
  );
  static const supplierSource = TranslatableString(
    en: 'Supplier / source',
    ar: 'المورد / المصدر',
    ur: 'سپلائر / ذریعہ',
    hi: 'आपूर्तिकर्ता / स्रोत',
  );
  static const rowNumber = TranslatableString(
    en: 'R No',
    ar: 'رقم البند',
    ur: 'قطار نمبر',
    hi: 'पंक्ति सं.',
  );
  static const arranged = TranslatableString(
    en: 'Arranged',
    ar: 'الكمية المرتبة',
    ur: 'انتظام شدہ',
    hi: 'व्यवस्थित',
  );
  static const decision = TranslatableString(
    en: 'Decision',
    ar: 'القرار',
    ur: 'فیصلہ',
    hi: 'निर्णय',
  );
  static const source = TranslatableString(
    en: 'Source',
    ar: 'المصدر',
    ur: 'ماخذ',
    hi: 'स्रोत',
  );
  static const warehouse = TranslatableString(
    en: 'Warehouse',
    ar: 'المستودع',
    ur: 'گودام',
    hi: 'वेयरहाउस',
  );
  static const externalSupplier = TranslatableString(
    en: 'External supplier',
    ar: 'مورد خارجي',
    ur: 'بیرونی سپلائر',
    hi: 'बाहरी आपूर्तिकर्ता',
  );
  static const supplierNameOptional = TranslatableString(
    en: 'Supplier name optional',
    ar: 'اسم المورد (اختياري)',
    ur: 'سپلائر کا نام (اختیاری)',
    hi: 'आपूर्तिकर्ता का नाम (वैकल्पिक)',
  );
  static const addSupplierDetails = TranslatableString(
    en: 'Add supplier details (optional)',
    ar: 'إضافة تفاصيل المورد (اختياري)',
    ur: 'سپلائر کی تفصیلات شامل کریں (اختیاری)',
    hi: 'आपूर्तिकर्ता विवरण जोड़ें (वैकल्पिक)',
  );
  static const optionalAvailabilityDetails = TranslatableString(
    en: 'Availability details (optional)',
    ar: 'تفاصيل التوفر (اختياري)',
    ur: 'دستیابی کی تفصیلات (اختیاری)',
    hi: 'उपलब्धता विवरण (वैकल्पिक)',
  );
  static const externalReadiness = TranslatableString(
    en: 'External source readiness',
    ar: 'جاهزية المصدر الخارجي',
    ur: 'بیرونی ذریعہ کی تیاری',
    hi: 'बाहरी स्रोत की तैयारी',
  );
  static const externalReadyConfirmed = TranslatableString(
    en: 'Quantity is available or firmly committed',
    ar: 'الكمية متاحة أو مؤكدة الالتزام',
    ur: 'مقدار دستیاب ہے یا پختہ طور پر طے ہے',
    hi: 'मात्रा उपलब्ध है या पक्की तरह प्रतिबद्ध है',
  );
  static const externalReadinessRecommended = TranslatableString(
    en: 'Recommended during adoption; Admin can make this mandatory.',
    ar: 'موصى به أثناء التطبيق؛ ويمكن للمسؤول جعله إلزامياً.',
    ur: 'اپنانے کے دوران تجویز کردہ؛ ایڈمن اسے لازمی بنا سکتا ہے۔',
    hi: 'अपनाने के दौरान अनुशंसित; एडमिन इसे अनिवार्य कर सकता है।',
  );
  static const externalReadinessRequired = TranslatableString(
    en: 'Required by the published Procurement policy.',
    ar: 'مطلوب وفق سياسة المشتريات المنشورة.',
    ur: 'شائع شدہ پروکیورمنٹ پالیسی کے مطابق ضروری ہے۔',
    hi: 'प्रकाशित खरीद नीति के अनुसार आवश्यक है।',
  );
  static const expectedAvailabilityDate = TranslatableString(
    en: 'Expected date (optional)',
    ar: 'التاريخ المتوقع (اختياري)',
    ur: 'متوقع تاریخ (اختیاری)',
    hi: 'अपेक्षित तारीख (वैकल्पिक)',
  );
  static const supplierReference = TranslatableString(
    en: 'Commitment / reference (optional)',
    ar: 'الالتزام / المرجع (اختياري)',
    ur: 'کمٹمنٹ / حوالہ (اختیاری)',
    hi: 'प्रतिबद्धता / संदर्भ (वैकल्पिक)',
  );
  static const warehouseItem = TranslatableString(
    en: 'Warehouse item',
    ar: 'صنف المستودع',
    ur: 'گودام آئٹم',
    hi: 'वेयरहाउस आइटम',
  );
  static const searchWarehouseItem = TranslatableString(
    en: 'Search warehouse items',
    ar: 'البحث في أصناف المستودع',
    ur: 'گودام کی اشیاء تلاش کریں',
    hi: 'वेयरहाउस आइटम खोजें',
  );
  static const createInventoryItem = TranslatableString(
    en: 'Create inventory item',
    ar: 'إنشاء صنف مخزون',
    ur: 'انوینٹری آئٹم بنائیں',
    hi: 'इन्वेंट्री आइटम बनाएं',
  );
  static const createInventoryItemHelp = TranslatableString(
    en: 'Create a controlled item master from this request line. New stock is recorded only when you enter a physical opening balance and reason.',
    ar: 'أنشئ صنف مخزون مضبوطاً من بند الطلب. لا يُسجل المخزون الجديد إلا عند إدخال رصيد افتتاحي فعلي وسبب.',
    ur: 'اس درخواست کی لائن سے کنٹرول شدہ انوینٹری آئٹم بنائیں۔ نیا اسٹاک صرف اس وقت ریکارڈ ہوتا ہے جب آپ حقیقی افتتاحی بیلنس اور وجہ درج کریں۔',
    hi: 'इस अनुरोध पंक्ति से नियंत्रित इन्वेंट्री आइटम बनाएं। नया स्टॉक केवल वास्तविक प्रारंभिक शेष और कारण दर्ज करने पर रिकॉर्ड होता है।',
  );
  static const inventoryItemCreated = TranslatableString(
    en: 'Inventory item created',
    ar: 'تم إنشاء صنف المخزون',
    ur: 'انوینٹری آئٹم بن گیا',
    hi: 'इन्वेंट्री आइटम बनाया गया',
  );
  static const createdItemHasNoAvailableStock = TranslatableString(
    en: 'The new item has no available stock. Receive physical stock before using it from Warehouse, or choose External supplier.',
    ar: 'لا يوجد مخزون متاح للصنف الجديد. استلم المخزون الفعلي قبل استخدامه من المستودع، أو اختر مورداً خارجياً.',
    ur: 'نئے آئٹم کا کوئی دستیاب اسٹاک نہیں ہے۔ گودام سے استعمال سے پہلے فزیکل اسٹاک وصول کریں، یا بیرونی سپلائر منتخب کریں۔',
    hi: 'नए आइटम में उपलब्ध स्टॉक नहीं है। वेयरहाउस से उपयोग करने से पहले भौतिक स्टॉक प्राप्त करें, या बाहरी आपूर्तिकर्ता चुनें।',
  );
  static const categoryRequiredForNewItem = TranslatableString(
    en: 'Choose an existing category or explicitly create a new parent category.',
    ar: 'اختر فئة موجودة أو أنشئ فئة رئيسية جديدة صراحةً.',
    ur: 'موجودہ کیٹیگری منتخب کریں یا واضح طور پر نئی پیرنٹ کیٹیگری بنائیں۔',
    hi: 'मौजूदा श्रेणी चुनें या स्पष्ट रूप से नई मूल श्रेणी बनाएं।',
  );
  static const newParentCategory = TranslatableString(
    en: 'Create as a new parent category',
    ar: 'إنشاء كفئة رئيسية جديدة',
    ur: 'نئی پیرنٹ کیٹیگری کے طور پر بنائیں',
    hi: 'नई मूल श्रेणी के रूप में बनाएं',
  );
  static const openingBalanceOptional = TranslatableString(
    en: 'Opening balance optional',
    ar: 'الرصيد الافتتاحي اختياري',
    ur: 'افتتاحی بیلنس اختیاری',
    hi: 'प्रारंभिक शेष वैकल्पिक',
  );
  static const physicalStockReason = TranslatableString(
    en: 'Physical stock reason',
    ar: 'سبب المخزون الفعلي',
    ur: 'فزیکل اسٹاک کی وجہ',
    hi: 'भौतिक स्टॉक का कारण',
  );
  static const availability = TranslatableString(
    en: 'Warehouse availability',
    ar: 'توفر المستودع',
    ur: 'گودام کی دستیابی',
    hi: 'वेयरहाउस उपलब्धता',
  );
  static const reserved = TranslatableString(
    en: 'Reserved',
    ar: 'محجوز',
    ur: 'محفوظ',
    hi: 'आरक्षित',
  );
  static const reason = TranslatableString(
    en: 'Reason / note',
    ar: 'السبب / الملاحظة',
    ur: 'وجہ / نوٹ',
    hi: 'कारण / नोट',
  );
  static const unitCost = TranslatableString(
    en: 'Unit cost',
    ar: 'تكلفة الوحدة',
    ur: 'فی یونٹ لاگت',
    hi: 'इकाई लागत',
  );
  static const procurementNote = TranslatableString(
    en: 'Procurement Note optional',
    ar: 'ملاحظة المشتريات (اختياري)',
    ur: 'پروکیورمنٹ نوٹ (اختیاری)',
    hi: 'खरीद टिप्पणी (वैकल्पिक)',
  );
  static const procurementNoteHint = TranslatableString(
    en: 'Overall availability, alternatives or expected delivery information',
    ar: 'التوفر العام أو البدائل أو معلومات التسليم المتوقعة',
    ur: 'مجموعی دستیابی، متبادل یا متوقع ڈیلیوری کی معلومات',
    hi: 'कुल उपलब्धता, विकल्प या अपेक्षित डिलीवरी जानकारी',
  );
  static const noSourceRequired = TranslatableString(
    en: 'No source required',
    ar: 'لا يلزم مصدر',
    ur: 'ماخذ درکار نہیں',
    hi: 'स्रोत आवश्यक नहीं',
  );
  static const reviewSummary = TranslatableString(
    en: 'Review summary',
    ar: 'ملخص المراجعة',
    ur: 'جائزہ خلاصہ',
    hi: 'समीक्षा सारांश',
  );
  static const version = TranslatableString(
    en: 'Version',
    ar: 'الإصدار',
    ur: 'ورژن',
    hi: 'संस्करण',
  );
  static const startedBy = TranslatableString(
    en: 'Started by',
    ar: 'بدأ بواسطة',
    ur: 'شروع کرنے والا',
    hi: 'शुरू करने वाला',
  );
  static const noArrangement = TranslatableString(
    en: 'No arrangement has been started for this request.',
    ar: 'لم يبدأ أي ترتيب لهذا الطلب.',
    ur: 'اس درخواست کے لیے کوئی انتظام شروع نہیں ہوا۔',
    hi: 'इस अनुरोध के लिए कोई व्यवस्था शुरू नहीं हुई है।',
  );
  static const savingFailed = TranslatableString(
    en: 'Could not save this arrangement. Refresh and review the current version.',
    ar: 'تعذر حفظ هذا الترتيب. حدّث وراجع الإصدار الحالي.',
    ur: 'یہ انتظام محفوظ نہیں ہو سکا۔ ریفریش کریں اور موجودہ ورژن دیکھیں۔',
    hi: 'यह व्यवस्था सहेजी नहीं जा सकी। रीफ़्रेश करके वर्तमान संस्करण देखें।',
  );
  static const arrangementSaved = TranslatableString(
    en: 'Arrangement saved and confirmed',
    ar: 'تم حفظ الترتيب وتأكيده',
    ur: 'انتظام محفوظ اور تصدیق شدہ ہے',
    hi: 'व्यवस्था सहेजी और पुष्ट की गई',
  );
  static TranslatableString arrangementSavedSummary({
    required int full,
    required int partial,
    required int unavailable,
  }) => TranslatableString(
    en: '$full full · $partial partial · $unavailable unavailable. Positive arranged quantities are ready for controlled dispatch.',
    ar: '$full كامل · $partial جزئي · $unavailable غير متاح. الكميات المرتبة الموجبة جاهزة للإرسال المنضبط.',
    ur: '$full مکمل · $partial جزوی · $unavailable غیر دستیاب۔ مثبت ترتیب شدہ مقدار کنٹرولڈ ڈسپیچ کے لیے تیار ہے۔',
    hi: '$full पूर्ण · $partial आंशिक · $unavailable अनुपलब्ध। सकारात्मक व्यवस्थित मात्राएँ नियंत्रित डिस्पैच के लिए तैयार हैं।',
  );
  static const stockChangedBeforeSave = TranslatableString(
    en: 'Warehouse availability changed before the arrangement could be saved. Review the refreshed stock, reduce the quantity, or choose Partial, Cannot Provide Now, or External supplier.',
    ar: 'تغيّر توفر المستودع قبل حفظ الترتيب. راجع المخزون المحدّث، أو قلّل الكمية، أو اختر جزئياً أو لا يمكن توفيره الآن أو مورداً خارجياً.',
    ur: 'انتظام محفوظ ہونے سے پہلے گودام کی دستیابی بدل گئی۔ تازہ شدہ ذخیرہ دیکھیں، مقدار کم کریں، یا جزوی، ابھی فراہم نہیں کیا جا سکتا، یا بیرونی سپلائر منتخب کریں۔',
    hi: 'व्यवस्था सहेजे जाने से पहले वेयरहाउस उपलब्धता बदल गई। अपडेट किए गए स्टॉक की समीक्षा करें, मात्रा घटाएं, या Partial, Cannot Provide Now या External supplier चुनें।',
  );
  static const invalidLines = TranslatableString(
    en: 'Complete every line. Partial and unavailable decisions need a reason.',
    ar: 'أكمل كل بند. القرارات الجزئية وغير المتاحة تحتاج سببًا.',
    ur: 'ہر سطر مکمل کریں۔ جزوی اور غیر دستیاب فیصلوں کے لیے وجہ ضروری ہے۔',
    hi: 'हर पंक्ति पूरी करें। आंशिक और अनुपलब्ध निर्णयों के लिए कारण चाहिए।',
  );

  static TranslatableString rowsNeedAttention(int count) => TranslatableString(
    en: '$count ${count == 1 ? 'row needs' : 'rows need'} attention before saving.',
    ar: '$count ${count == 1 ? 'صف يحتاج' : 'صفوف تحتاج'} إلى المراجعة قبل الحفظ.',
    ur: 'محفوظ کرنے سے پہلے $count ${count == 1 ? 'قطار' : 'قطاروں'} پر توجہ درکار ہے۔',
    hi: 'सहेजने से पहले $count ${count == 1 ? 'पंक्ति' : 'पंक्तियों'} पर ध्यान देना आवश्यक है।',
  );

  static TranslatableString validationItem(int number) => TranslatableString(
    en: 'Item $number',
    ar: 'البند $number',
    ur: 'آئٹم $number',
    hi: 'आइटम $number',
  );

  static TranslatableString itemPosition(int item, int total) =>
      TranslatableString(
        en: 'Item $item of $total',
        ar: 'البند $item من $total',
        ur: 'آئٹم $item از $total',
        hi: 'वस्तु $item / $total',
      );

  static TranslatableString linesDecided(int decided, int total) =>
      TranslatableString(
        en: '$decided / $total quantities entered',
        ar: 'تم إدخال $decided من $total كمية',
        ur: '$decided / $total مقدار درج',
        hi: '$decided / $total मात्राएँ दर्ज',
      );

  static TranslatableString exceptionsRequireAttention(int count) =>
      TranslatableString(
        en: '$count exceptions require attention',
        ar: '$count استثناءات تحتاج إلى الانتباه',
        ur: '$count استثنائی لائنز توجہ چاہتی ہیں',
        hi: '$count अपवादों पर ध्यान आवश्यक है',
      );

  static TranslatableString exceptionSummary(
    int partial,
    int unavailable,
  ) => TranslatableString(
    en: '$partial partial and $unavailable unavailable lines remain explicit.',
    ar: 'تبقى $partial بنود جزئية و$unavailable بنود غير متاحة موضحة بوضوح.',
    ur: '$partial جزوی اور $unavailable غیر دستیاب لائنز واضح رہتی ہیں۔',
    hi: '$partial आंशिक और $unavailable अनुपलब्ध पंक्तियाँ स्पष्ट रहती हैं।',
  );

  static TranslatableString invalidQuantityFor(String line) =>
      TranslatableString(
        en: '$line needs a valid arranged quantity.',
        ar: 'يحتاج $line إلى كمية مرتبة صالحة.',
        ur: '$line کے لیے درست ترتیب شدہ مقدار درکار ہے۔',
        hi: '$line के लिए मान्य व्यवस्थित मात्रा आवश्यक है।',
      );

  static TranslatableString unavailableReasonFor(
    String line,
  ) => TranslatableString(
    en: '$line must have quantity 0 and a reason when it cannot be provided.',
    ar: 'يجب أن تكون كمية $line صفرًا مع سبب عند تعذر التوفير.',
    ur: 'فراہم نہ ہونے کی صورت میں $line کی مقدار 0 اور وجہ ضروری ہے۔',
    hi: 'उपलब्ध न होने पर $line की मात्रा 0 और कारण आवश्यक है।',
  );

  static TranslatableString warehouseItemRequiredFor(String line) =>
      TranslatableString(
        en: '$line needs a warehouse item before it can be reserved.',
        ar: 'يحتاج $line إلى صنف مستودع قبل حجزه.',
        ur: '$line کو ریزرو کرنے سے پہلے گودام کی آئٹم درکار ہے۔',
        hi: '$line को आरक्षित करने से पहले वेयरहाउस आइटम चाहिए।',
      );

  static TranslatableString warehouseStockShortageFor({
    required String line,
    required String item,
    required String requiredQuantity,
    required String availableQuantity,
    required String unit,
  }) => TranslatableString(
    en: '$line cannot reserve $item: $requiredQuantity $unit is arranged but only $availableQuantity $unit is available. Reduce the quantity, choose Partial or Cannot Provide Now, or use External supplier.',
    ar: 'لا يمكن لـ $line حجز $item: تم ترتيب $requiredQuantity $unit والمتاح فقط $availableQuantity $unit. قلّل الكمية، أو اختر جزئياً أو لا يمكن توفيره الآن، أو استخدم مورداً خارجياً.',
    ur: '$line، $item ریزرو نہیں کر سکتی: $requiredQuantity $unit کا انتظام ہے لیکن صرف $availableQuantity $unit دستیاب ہے۔ مقدار کم کریں، جزوی یا ابھی فراہم نہیں کیا جا سکتا منتخب کریں، یا بیرونی سپلائر استعمال کریں۔',
    hi: '$line, $item को आरक्षित नहीं कर सकती: $requiredQuantity $unit व्यवस्थित है, लेकिन केवल $availableQuantity $unit उपलब्ध है। मात्रा घटाएं, Partial या Cannot Provide Now चुनें, या External supplier का उपयोग करें।',
  );

  static TranslatableString emptyWarehouseFor(String line) =>
      TranslatableString(
        en: 'Warehouse inventory is empty. Select External supplier for $line.',
        ar: 'مخزون المستودع فارغ. اختر مورداً خارجياً لـ $line.',
        ur: 'گودام کا ذخیرہ خالی ہے۔ $line کے لیے بیرونی سپلائر منتخب کریں۔',
        hi: 'वेयरहाउस इन्वेंट्री खाली है। $line के लिए बाहरी सप्लायर चुनें।',
      );

  static TranslatableString partialReasonFor(String line) => TranslatableString(
    en: '$line needs a reason for a partial decision.',
    ar: 'يحتاج $line إلى سبب للقرار الجزئي.',
    ur: '$line کے جزوی فیصلے کے لیے وجہ درکار ہے۔',
    hi: '$line के आंशिक निर्णय के लिए कारण चाहिए।',
  );

  static TranslatableString fullQuantityFor(String line) => TranslatableString(
    en: '$line must match the requested quantity when marked Full.',
    ar: 'يجب أن تطابق كمية $line الكمية المطلوبة عند اختيار كامل.',
    ur: 'مکمل منتخب ہونے پر $line کی مقدار مطلوبہ مقدار کے برابر ہونی چاہیے۔',
    hi: 'Full चुनने पर $line की मात्रा अनुरोधित मात्रा के बराबर होनी चाहिए।',
  );

  static TranslatableString partialQuantityFor(
    String line,
  ) => TranslatableString(
    en: '$line must be greater than zero and less than the requested quantity when marked Partial.',
    ar: 'يجب أن تكون كمية $line أكبر من صفر وأقل من المطلوبة عند اختيار جزئي.',
    ur: 'جزوی منتخب ہونے پر $line کی مقدار صفر سے زیادہ اور مطلوبہ مقدار سے کم ہونی چاہیے۔',
    hi: 'Partial चुनने पर $line की मात्रा शून्य से अधिक और अनुरोधित मात्रा से कम होनी चाहिए।',
  );

  static TranslatableString invalidUnitCostFor(String line) =>
      TranslatableString(
        en: '$line needs a valid non-negative unit cost, or leave it blank.',
        ar: 'يحتاج $line إلى تكلفة وحدة صالحة غير سالبة أو اتركها فارغة.',
        ur: '$line کے لیے درست غیر منفی یونٹ لاگت درج کریں یا خالی چھوڑ دیں۔',
        hi: '$line के लिए वैध गैर-नकारात्मक यूनिट लागत दें या खाली छोड़ दें।',
      );
}

TranslatableString yorksV1ArrangementSourceCopy(
  YorksV1ArrangementSource source,
) => switch (source) {
  YorksV1ArrangementSource.warehouse => YorksV1ArrangementStrings.warehouse,
  YorksV1ArrangementSource.externalSupplier =>
    YorksV1ArrangementStrings.externalSupplier,
};

TranslatableString yorksV1ArrangementDecisionCopy(
  YorksV1ArrangementDecision decision,
) => switch (decision) {
  YorksV1ArrangementDecision.full => const TranslatableString(
    en: 'Full',
    ar: 'كامل',
    ur: 'مکمل',
    hi: 'पूर्ण',
  ),
  YorksV1ArrangementDecision.partial => const TranslatableString(
    en: 'Partial',
    ar: 'جزئي',
    ur: 'جزوی',
    hi: 'आंशिक',
  ),
  YorksV1ArrangementDecision.unavailable => const TranslatableString(
    en: 'Cannot Provide Now',
    ar: 'لا يمكن التوفير الآن',
    ur: 'ابھی فراہم نہیں ہو سکتا',
    hi: 'अभी उपलब्ध नहीं',
  ),
};

TranslatableString yorksV1ArrangementStatusCopy(
  YorksV1ArrangementStatus status,
) => switch (status) {
  YorksV1ArrangementStatus.working => const TranslatableString(
    en: 'Working',
    ar: 'قيد العمل',
    ur: 'کام جاری ہے',
    hi: 'कार्यरत',
  ),
  YorksV1ArrangementStatus.awaitingApproval => const TranslatableString(
    en: 'Awaiting approval',
    ar: 'بانتظار الموافقة',
    ur: 'منظوری کا انتظار',
    hi: 'मंजूरी की प्रतीक्षा',
  ),
  YorksV1ArrangementStatus.approved => const TranslatableString(
    en: 'Approved',
    ar: 'معتمد',
    ur: 'منظور شدہ',
    hi: 'स्वीकृत',
  ),
  YorksV1ArrangementStatus.returned => const TranslatableString(
    en: 'Returned for changes',
    ar: 'أعيد للتعديل',
    ur: 'تبدیلی کے لیے واپس',
    hi: 'बदलाव के लिए लौटाया',
  ),
  YorksV1ArrangementStatus.superseded => const TranslatableString(
    en: 'Replaced',
    ar: 'تم استبداله',
    ur: 'تبدیل شدہ',
    hi: 'प्रतिस्थापित',
  ),
  YorksV1ArrangementStatus.cancelled => const TranslatableString(
    en: 'Cancelled',
    ar: 'ملغى',
    ur: 'منسوخ',
    hi: 'रद्द',
  ),
};
