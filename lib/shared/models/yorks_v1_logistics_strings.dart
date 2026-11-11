import 'app_strings.dart';
import 'yorks_v1_company_document_strings.dart';
import 'yorks_v1_logistics.dart';

/// Centralized user-facing copy for the Batch 7 warehouse and logistics flow.
abstract final class YorksV1LogisticsStrings {
  static const reviewDispatch = TranslatableString(
    en: 'Review dispatch',
    ar: 'مراجعة الإرسال',
    ur: 'ترسیل کا جائزہ',
    hi: 'डिस्पैच की समीक्षा',
  );
  static const confirmDispatch = TranslatableString(
    en: 'Confirm dispatch',
    ar: 'تأكيد الإرسال',
    ur: 'ترسیل کی تصدیق',
    hi: 'डिस्पैच की पुष्टि',
  );
  static const editDispatch = TranslatableString(
    en: 'Back to editing',
    ar: 'العودة للتحرير',
    ur: 'ترمیم پر واپس',
    hi: 'संपादन पर वापस',
  );
  static const dispatchReviewHelp = TranslatableString(
    en: 'Check the destination and quantities. Confirming dispatch commits warehouse stock once.',
    ar: 'تحقق من الوجهة والكميات. تأكيد الإرسال يخصم مخزون المستودع مرة واحدة.',
    ur: 'منزل اور مقدار چیک کریں۔ تصدیق سے گودام کا اسٹاک ایک بار کم ہوگا۔',
    hi: 'गंतव्य और मात्रा जाँचें। पुष्टि पर गोदाम का स्टॉक एक बार घटेगा।',
  );
  static const sendNow = TranslatableString(
    en: 'Send now',
    ar: 'إرسال الآن',
    ur: 'ابھی بھیجیں',
    hi: 'अभी भेजें',
  );
  static const dispatchQuantityNegative = TranslatableString(
    en: 'Enter zero or a positive quantity.',
    ar: 'أدخل صفرًا أو كمية موجبة.',
    ur: 'صفر یا مثبت مقدار درج کریں۔',
    hi: 'शून्य या धनात्मक मात्रा दर्ज करें।',
  );
  static const dispatchQuantityInvalid = TranslatableString(
    en: 'Enter a number with up to 4 decimal places.',
    ar: 'أدخل رقمًا حتى 4 منازل عشرية.',
    ur: 'چار اعشاری مقامات تک عدد درج کریں۔',
    hi: 'चार दशमलव स्थानों तक संख्या दर्ज करें।',
  );
  static const dispatchQuantityRemaining = TranslatableString(
    en: 'Quantity exceeds the approved amount still needed.',
    ar: 'الكمية تتجاوز المتبقي المعتمد.',
    ur: 'مقدار منظور شدہ باقی مقدار سے زیادہ ہے۔',
    hi: 'मात्रा स्वीकृत शेष से अधिक है।',
  );
  static const dispatchQuantityStock = TranslatableString(
    en: 'Combined quantities exceed available stock for this item.',
    ar: 'الكميات المجمعة تتجاوز المخزون المتاح لهذا الصنف.',
    ur: 'اس آئٹم کی مجموعی مقدار دستیاب اسٹاک سے زیادہ ہے۔',
    hi: 'इस वस्तु की कुल मात्रा उपलब्ध स्टॉक से अधिक है।',
  );
  static const dispatchStockUnknown = TranslatableString(
    en: 'Stock is unavailable. Refresh before reviewing.',
    ar: 'المخزون غير متاح. حدّث قبل المراجعة.',
    ur: 'اسٹاک دستیاب نہیں۔ جائزے سے پہلے تازہ کریں۔',
    hi: 'स्टॉक उपलब्ध नहीं। समीक्षा से पहले रीफ़्रेश करें।',
  );
  static const dispatchExcluded = TranslatableString(
    en: 'Blank or zero quantities are not included.',
    ar: 'لا تشمل الكميات الفارغة أو الصفرية.',
    ur: 'خالی یا صفر مقدار شامل نہیں۔',
    hi: 'खाली या शून्य मात्राएँ शामिल नहीं हैं।',
  );
  static const dispatchNoteSnapshot = TranslatableString(
    en: 'Delivery note · dispatched quantities',
    ar: 'إشعار تسليم · الكميات المرسلة',
    ur: 'ڈیلیوری نوٹ · بھیجی گئی مقدار',
    hi: 'डिलीवरी नोट · भेजी गई मात्रा',
  );
  static const receiptReportSnapshot = TranslatableString(
    en: 'Delivery report · received quantities',
    ar: 'تقرير تسليم · الكميات المستلمة',
    ur: 'ڈیلیوری رپورٹ · موصول مقدار',
    hi: 'डिलीवरी रिपोर्ट · प्राप्त मात्रा',
  );
  static const documentRevision = TranslatableString(
    en: 'Document revision',
    ar: 'إصدار المستند',
    ur: 'دستاویز کا ورژن',
    hi: 'दस्तावेज़ संस्करण',
  );
  static const dispatchHistoryOpen = TranslatableString(
    en: 'View dispatch history',
    ar: 'عرض سجل الإرسال',
    ur: 'ترسیل کی تاریخ دیکھیں',
    hi: 'डिस्पैच इतिहास देखें',
  );
  static const prepareDispatch = TranslatableString(
    en: 'Prepare dispatch',
    ar: 'إعداد الإرسال',
    ur: 'ترسیل تیار کریں',
    hi: 'डिस्पैच तैयार करें',
  );
  static TranslatableString dispatchSelection(int included, int omitted) =>
      TranslatableString(
        en: '$included lines included · $omitted not included',
        ar: '$included بنود مشمولة · $omitted غير مشمولة',
        ur: '$included لائنیں شامل · $omitted شامل نہیں',
        hi: '$included पंक्तियाँ शामिल · $omitted शामिल नहीं',
      );
  static const addSitePhoto = TranslatableString(
    en: 'Add site photo',
    ar: 'إضافة صورة من الموقع',
    ur: 'سائٹ کی تصویر شامل کریں',
    hi: 'साइट की तस्वीर जोड़ें',
  );
  static const sitePhotoUploaded = TranslatableString(
    en: 'Site photo attached',
    ar: 'تم إرفاق صورة الموقع',
    ur: 'سائٹ کی تصویر منسلک ہو گئی',
    hi: 'साइट की तस्वीर संलग्न हो गई',
  );
  static const sitePhotoFailed = TranslatableString(
    en: 'The site photo could not be attached. Please try again.',
    ar: 'تعذر إرفاق صورة الموقع. يرجى المحاولة مرة أخرى.',
    ur: 'سائٹ کی تصویر منسلک نہیں ہو سکی۔ دوبارہ کوشش کریں۔',
    hi: 'साइट की तस्वीर संलग्न नहीं हो सकी। कृपया फिर से प्रयास करें।',
  );
  static const receiptConfirmed = TranslatableString(
    en: 'Receipt confirmed',
    ar: 'تم تأكيد الاستلام',
    ur: 'وصولی کی تصدیق ہو گئی',
    hi: 'प्राप्ति की पुष्टि हो गई',
  );
  static TranslatableString receiptConfirmedSummary({
    required int lines,
    required int exceptionLines,
  }) => TranslatableString(
    en: '$lines ${lines == 1 ? 'line' : 'lines'} confirmed · $exceptionLines ${exceptionLines == 1 ? 'exception' : 'exceptions'} recorded.',
    ar: 'تم تأكيد $lines من البنود · تم تسجيل $exceptionLines من الاستثناءات.',
    ur: '$lines لائنوں کی تصدیق · $exceptionLines استثناء ریکارڈ ہوئے۔',
    hi: '$lines पंक्तियाँ पुष्ट · $exceptionLines अपवाद दर्ज।',
  );
  static const attachPhotoPrompt = TranslatableString(
    en: 'Would you like to attach a site photo to this confirmed receipt?',
    ar: 'هل ترغب في إرفاق صورة من الموقع بهذا الاستلام المؤكد؟',
    ur: 'کیا آپ اس تصدیق شدہ وصولی کے ساتھ سائٹ کی تصویر منسلک کرنا چاہتے ہیں؟',
    hi: 'क्या आप इस पुष्ट प्राप्ति के साथ साइट की तस्वीर संलग्न करना चाहेंगे?',
  );
  static const attachLater = TranslatableString(
    en: 'Attach later',
    ar: 'إرفاق لاحقًا',
    ur: 'بعد میں منسلک کریں',
    hi: 'बाद में संलग्न करें',
  );
  static const companyName = YorksV1CompanyDocumentStrings.legalName;
  static const deliveryOrderTitle = TranslatableString(
    en: 'DELIVERY ORDER',
    ar: 'أمر تسليم',
    ur: 'ڈیلیوری آرڈر',
    hi: 'डिलीवरी ऑर्डर',
  );
  static const deliveryReportTitle = TranslatableString(
    en: 'DELIVERY REPORT',
    ar: 'تقرير التسليم',
    ur: 'ڈیلیوری رپورٹ',
    hi: 'डिलीवरी रिपोर्ट',
  );
  static const reference = TranslatableString(
    en: 'Ref.',
    ar: 'المرجع',
    ur: 'حوالہ',
    hi: 'संदर्भ',
  );
  static const date = TranslatableString(
    en: 'Date',
    ar: 'التاريخ',
    ur: 'تاریخ',
    hi: 'दिनांक',
  );
  static const recipient = TranslatableString(
    en: 'M/s.',
    ar: 'السادة',
    ur: 'برائے',
    hi: 'प्रति',
  );
  static const deliveryAddress = TranslatableString(
    en: 'Delivery Address',
    ar: 'عنوان التسليم',
    ur: 'ڈیلیوری کا پتہ',
    hi: 'डिलीवरी पता',
  );
  static const inspectedAndChecked = TranslatableString(
    en: 'Inspected & checked by Yorks',
    ar: 'تم الفحص والتحقق بواسطة يوركس',
    ur: 'Yorks نے معائنہ اور جانچ کی',
    hi: 'Yorks द्वारा निरीक्षण और जाँच',
  );
  static const receiverName = TranslatableString(
    en: "Receiver's Name",
    ar: 'اسم المستلم',
    ur: 'وصول کنندہ کا نام',
    hi: 'प्राप्तकर्ता का नाम',
  );
  static const signature = TranslatableString(
    en: 'Signature / Date',
    ar: 'التوقيع / التاريخ',
    ur: 'دستخط / تاریخ',
    hi: 'हस्ताक्षर / दिनांक',
  );
  static const goodsReceivedInGoodCondition = TranslatableString(
    en: 'GOODS RECEIVED IN GOOD CONDITION',
    ar: 'تم استلام البضائع بحالة جيدة',
    ur: 'سامان اچھی حالت میں وصول ہوا',
    hi: 'सामान अच्छी स्थिति में प्राप्त हुआ',
  );
  static const receiptReviewedQuantities = TranslatableString(
    en: 'RECEIPT-REVIEWED QUANTITIES',
    ar: 'الكميات المؤكدة بعد مراجعة الاستلام',
    ur: 'رسید کے جائزے کے بعد تصدیق شدہ مقداریں',
    hi: 'रसीद समीक्षा के बाद पुष्ट मात्राएँ',
  );
  static const serialNumber = TranslatableString(
    en: 'S:No',
    ar: 'م',
    ur: 'نمبر',
    hi: 'क्र.',
  );
  static const deliveryQuantity = TranslatableString(
    en: 'Qty',
    ar: 'الكمية',
    ur: 'مقدار',
    hi: 'मात्रा',
  );
  static const state = TranslatableString(
    en: 'State',
    ar: 'الحالة',
    ur: 'حالت',
    hi: 'स्थिति',
  );
  static const draftedBy = TranslatableString(
    en: 'Drafted by',
    ar: 'أعده',
    ur: 'تیار کنندہ',
    hi: 'ड्राफ़्ट करने वाला',
  );
  static const inventory = TranslatableString(
    en: 'Warehouse inventory',
    ar: 'مخزون المستودع',
    ur: 'گودام کا ذخیرہ',
    hi: 'वेयरहाउस इन्वेंटरी',
  );
  static const refresh = TranslatableString(
    en: 'Refresh',
    ar: 'تحديث',
    ur: 'ریفریش',
    hi: 'रीफ़्रेश',
  );
  static const dispatchAndReceipt = TranslatableString(
    en: 'Dispatch and receipt',
    ar: 'الإرسال والاستلام',
    ur: 'ڈسپیچ اور وصولی',
    hi: 'डिस्पैच और प्राप्ति',
  );
  static const dispatchCentre = TranslatableString(
    en: 'Dispatch Centre',
    ar: 'مركز الإرسال',
    ur: 'ڈسپیچ سینٹر',
    hi: 'डिस्पैच केंद्र',
  );
  static const dispatchCentreDescription = TranslatableString(
    en: 'Track dispatches, delivery documents and site receipt across authorized projects.',
    ar: 'تتبع عمليات الإرسال ومستندات التسليم واستلام الموقع عبر المشاريع المصرح بها.',
    ur: 'مجاز پروجیکٹس میں ڈسپیچ، ڈیلیوری دستاویزات اور سائٹ وصولی کو ٹریک کریں۔',
    hi: 'अधिकृत परियोजनाओं में डिस्पैच, डिलीवरी दस्तावेज़ और साइट प्राप्ति को ट्रैक करें।',
  );
  static const totalDispatchRequests = TranslatableString(
    en: 'Dispatch requests',
    ar: 'طلبات الإرسال',
    ur: 'ڈسپیچ درخواستیں',
    hi: 'डिस्पैच अनुरोध',
  );
  static const readyToDispatch = TranslatableString(
    en: 'Ready to dispatch',
    ar: 'جاهز للإرسال',
    ur: 'ڈسپیچ کے لیے تیار',
    hi: 'डिस्पैच के लिए तैयार',
  );
  static const receiptReviewRequired = TranslatableString(
    en: 'Receipt review required',
    ar: 'مطلوب مراجعة الاستلام',
    ur: 'وصولی کا جائزہ درکار ہے',
    hi: 'प्राप्ति समीक्षा आवश्यक',
  );
  static const completedDeliveries = TranslatableString(
    en: 'Completed deliveries',
    ar: 'عمليات التسليم المكتملة',
    ur: 'مکمل ڈیلیوریز',
    hi: 'पूर्ण डिलीवरी',
  );
  static const projectFolders = TranslatableString(
    en: 'Project folders',
    ar: 'مجلدات المشاريع',
    ur: 'پروجیکٹ فولڈرز',
    hi: 'परियोजना फ़ोल्डर',
  );
  static const allDispatches = TranslatableString(
    en: 'All dispatches',
    ar: 'جميع عمليات الإرسال',
    ur: 'تمام ڈسپیچز',
    hi: 'सभी डिस्पैच',
  );
  static const attentionRequired = TranslatableString(
    en: 'Attention required',
    ar: 'يتطلب الانتباه',
    ur: 'توجہ درکار ہے',
    hi: 'ध्यान देना आवश्यक',
  );
  static const completedArchive = TranslatableString(
    en: 'Completed archive',
    ar: 'أرشيف المكتمل',
    ur: 'مکمل آرکائیو',
    hi: 'पूर्ण अभिलेख',
  );
  static const dispatchRegister = TranslatableString(
    en: 'Dispatch register',
    ar: 'سجل الإرسال',
    ur: 'ڈسپیچ رجسٹر',
    hi: 'डिस्पैच रजिस्टर',
  );
  static const searchDispatches = TranslatableString(
    en: 'Search request, project, scope or requester...',
    ar: 'البحث في الطلب أو المشروع أو النطاق أو مقدم الطلب...',
    ur: 'درخواست، پروجیکٹ، دائرہ یا درخواست دہندہ تلاش کریں...',
    hi: 'अनुरोध, परियोजना, दायरा या अनुरोधकर्ता खोजें...',
  );
  static const noDispatchMatches = TranslatableString(
    en: 'No dispatch records match the current search and filters.',
    ar: 'لا توجد سجلات إرسال تطابق البحث وعوامل التصفية الحالية.',
    ur: 'موجودہ تلاش اور فلٹرز سے کوئی ڈسپیچ ریکارڈ نہیں ملا۔',
    hi: 'वर्तमान खोज और फ़िल्टर से कोई डिस्पैच रिकॉर्ड मेल नहीं खाता।',
  );
  static const openDispatchWorkflow = TranslatableString(
    en: 'Open workflow',
    ar: 'فتح سير العمل',
    ur: 'ورک فلو کھولیں',
    hi: 'वर्कफ़्लो खोलें',
  );
  static const printMaterialRequest = TranslatableString(
    en: 'Print Material Request',
    ar: 'طباعة طلب المواد',
    ur: 'میٹریل ریکویسٹ پرنٹ کریں',
    hi: 'सामग्री अनुरोध प्रिंट करें',
  );
  static const printDeliveryReport = TranslatableString(
    en: 'Print Delivery Report',
    ar: 'طباعة تقرير التسليم',
    ur: 'ڈیلیوری رپورٹ پرنٹ کریں',
    hi: 'डिलीवरी रिपोर्ट प्रिंट करें',
  );
  static const deliveryReportUnavailable = TranslatableString(
    en: 'Generate the Delivery Order before printing this report.',
    ar: 'أنشئ أمر التسليم قبل طباعة هذا التقرير.',
    ur: 'یہ رپورٹ پرنٹ کرنے سے پہلے ڈیلیوری آرڈر بنائیں۔',
    hi: 'इस रिपोर्ट को प्रिंट करने से पहले डिलीवरी ऑर्डर बनाएं।',
  );
  static const project = TranslatableString(
    en: 'Project',
    ar: 'المشروع',
    ur: 'پروجیکٹ',
    hi: 'परियोजना',
  );
  static const scope = TranslatableString(
    en: 'Building / scope',
    ar: 'المبنى / النطاق',
    ur: 'عمارت / دائرہ',
    hi: 'भवन / दायरा',
  );
  static const searchInventory = TranslatableString(
    en: 'Search inventory',
    ar: 'بحث في المخزون',
    ur: 'ذخیرہ تلاش کریں',
    hi: 'इन्वेंटरी खोजें',
  );
  static const addStock = TranslatableString(
    en: 'Add or adjust stock',
    ar: 'إضافة أو تعديل المخزون',
    ur: 'اسٹاک شامل یا ایڈجسٹ کریں',
    hi: 'स्टॉक जोड़ें या समायोजित करें',
  );
  static const itemDescription = TranslatableString(
    en: 'Item Description',
    ar: 'وصف الصنف',
    ur: 'آئٹم کی تفصیل',
    hi: 'आइटम विवरण',
  );
  static const itemSize = TranslatableString(
    en: 'Size',
    ar: 'المقاس',
    ur: 'سائز',
    hi: 'आकार',
  );
  static const itemModel = TranslatableString(
    en: 'Model',
    ar: 'الموديل',
    ur: 'ماڈل',
    hi: 'मॉडल',
  );
  static const notProvided = TranslatableString(
    en: 'Not provided',
    ar: 'غير متوفر',
    ur: 'فراہم نہیں کیا گیا',
    hi: 'प्रदान नहीं किया गया',
  );
  static const brandOrigin = TranslatableString(
    en: 'Brand / origin',
    ar: 'العلامة / المنشأ',
    ur: 'برانڈ / ماخذ',
    hi: 'ब्रांड / मूल',
  );
  static const unit = TranslatableString(
    en: 'Unit',
    ar: 'الوحدة',
    ur: 'یونٹ',
    hi: 'इकाई',
  );
  static const quantity = TranslatableString(
    en: 'Quantity',
    ar: 'الكمية',
    ur: 'مقدار',
    hi: 'मात्रा',
  );
  static const reason = TranslatableString(
    en: 'Reason',
    ar: 'السبب',
    ur: 'وجہ',
    hi: 'कारण',
  );
  static const onHand = TranslatableString(
    en: 'On hand',
    ar: 'المتوفر فعلياً',
    ur: 'موجودہ اسٹاک',
    hi: 'हाथ में',
  );
  static const reserved = TranslatableString(
    en: 'Reserved',
    ar: 'محجوز',
    ur: 'محفوظ',
    hi: 'आरक्षित',
  );
  static const available = TranslatableString(
    en: 'Available',
    ar: 'المتاح',
    ur: 'دستیاب',
    hi: 'उपलब्ध',
  );
  static const movementHistory = TranslatableString(
    en: 'Movement history',
    ar: 'سجل الحركات',
    ur: 'حرکت کی تاریخ',
    hi: 'मूवमेंट इतिहास',
  );
  static const archive = TranslatableString(
    en: 'Archive item',
    ar: 'أرشفة الصنف',
    ur: 'آئٹم آرکائیو کریں',
    hi: 'आइटम संग्रहित करें',
  );
  static const reactivate = TranslatableString(
    en: 'Reactivate item',
    ar: 'إعادة تفعيل الصنف',
    ur: 'آئٹم دوبارہ فعال کریں',
    hi: 'आइटम फिर सक्रिय करें',
  );
  static const noInventory = TranslatableString(
    en: 'No warehouse items match this search.',
    ar: 'لا توجد أصناف مستودع مطابقة لهذا البحث.',
    ur: 'اس تلاش سے کوئی گودام آئٹم نہیں ملا۔',
    hi: 'इस खोज से कोई वेयरहाउस आइटम नहीं मिला।',
  );
  static const dispatchNow = TranslatableString(
    en: 'Dispatch now',
    ar: 'إرسال الآن',
    ur: 'ابھی ڈسپیچ کریں',
    hi: 'अभी डिस्पैच करें',
  );
  static const createDispatch = TranslatableString(
    en: 'Create Dispatch',
    ar: 'إنشاء إرسال',
    ur: 'ڈسپیچ بنائیں',
    hi: 'डिस्पैच बनाएँ',
  );
  static const dispatchOutstandingOnly = TranslatableString(
    en: 'Dispatch only the outstanding approved quantity.',
    ar: 'أرسل فقط الكمية المعتمدة المتبقية.',
    ur: 'صرف باقی منظور شدہ مقدار ڈسپیچ کریں۔',
    hi: 'केवल शेष स्वीकृत मात्रा भेजें।',
  );
  static const stockProtected = TranslatableString(
    en: 'Stock is protected',
    ar: 'المخزون محمي',
    ur: 'اسٹاک محفوظ ہے',
    hi: 'स्टॉक सुरक्षित है',
  );
  static const stockRecheckedOnDispatch = TranslatableString(
    en: 'Warehouse availability is rechecked and locked when the dispatch commits.',
    ar: 'تتم إعادة فحص توفر المستودع وقفله عند اعتماد الإرسال.',
    ur: 'ڈسپیچ کی تصدیق پر گودام کی دستیابی دوبارہ جانچ کر لاک کی جاتی ہے۔',
    hi: 'डिस्पैच प्रतिबद्ध होने पर वेयरहाउस उपलब्धता दोबारा जाँचकर लॉक की जाती है।',
  );
  static const dispatchApprovedItems = TranslatableString(
    en: 'Dispatch Approved Items',
    ar: 'إرسال العناصر المعتمدة',
    ur: 'منظور شدہ آئٹمز ڈسپیچ کریں',
    hi: 'स्वीकृत वस्तुएँ भेजें',
  );
  static const dispatched = TranslatableString(
    en: 'dispatched',
    ar: 'تم إرساله',
    ur: 'ڈسپیچ کیا گیا',
    hi: 'भेजा गया',
  );
  static const dispatchConfirmed = TranslatableString(
    en: 'Dispatch committed',
    ar: 'تم اعتماد الإرسال',
    ur: 'ڈسپیچ مکمل ہو گیا',
    hi: 'डिस्पैच प्रतिबद्ध हुआ',
  );
  static TranslatableString dispatchConfirmedSummary({
    required String number,
    required int lines,
  }) => TranslatableString(
    en: '$number · $lines ${lines == 1 ? 'line' : 'lines'} committed · Receipt review is next.',
    ar: '$number · تم اعتماد $lines من البنود · مراجعة الاستلام هي الخطوة التالية.',
    ur: '$number · $lines لائنیں مکمل · اگلا مرحلہ وصولی کا جائزہ ہے۔',
    hi: '$number · $lines पंक्तियाँ प्रतिबद्ध · अगला चरण प्राप्ति समीक्षा है।',
  );
  static const dispatchDate = TranslatableString(
    en: 'Dispatch date',
    ar: 'تاريخ الإرسال',
    ur: 'ڈسپیچ تاریخ',
    hi: 'डिस्पैच तारीख',
  );
  static const dispatchNumber = TranslatableString(
    en: 'Dispatch no.',
    ar: 'رقم الإرسال',
    ur: 'ڈسپیچ نمبر',
    hi: 'डिस्पैच नंबर',
  );
  static const dispatchedBy = TranslatableString(
    en: 'Dispatched by',
    ar: 'تم الإرسال بواسطة',
    ur: 'ڈسپیچ کرنے والا',
    hi: 'इसके द्वारा डिस्पैच',
  );
  static const source = TranslatableString(
    en: 'Source',
    ar: 'المصدر',
    ur: 'ذریعہ',
    hi: 'स्रोत',
  );
  static const deliveryReference = TranslatableString(
    en: 'Delivery Note / Dispatch Ref.',
    ar: 'مرجع إذن التسليم / الإرسال',
    ur: 'ڈیلیوری نوٹ / ڈسپیچ حوالہ',
    hi: 'डिलीवरी नोट / डिस्पैच रेफ़रेंस',
  );
  static const optionalSupplierReference = TranslatableString(
    en: 'Supplier delivery reference (optional)',
    ar: 'مرجع تسليم المورد (اختياري)',
    ur: 'سپلائر ڈیلیوری حوالہ (اختیاری)',
    hi: 'आपूर्तिकर्ता डिलीवरी संदर्भ (वैकल्पिक)',
  );
  static const deliveryReferenceRequired = TranslatableString(
    en: 'Enter the Delivery Note / Dispatch Reference before dispatching.',
    ar: 'أدخل مرجع إذن التسليم / الإرسال قبل الإرسال.',
    ur: 'ڈسپیچ سے پہلے ڈیلیوری نوٹ / ڈسپیچ حوالہ درج کریں۔',
    hi: 'डिस्पैच करने से पहले डिलीवरी नोट / डिस्पैच रेफ़रेंस दर्ज करें।',
  );
  static const driver = TranslatableString(
    en: 'Driver (optional)',
    ar: 'السائق (اختياري)',
    ur: 'ڈرائیور (اختیاری)',
    hi: 'ड्राइवर (वैकल्पिक)',
  );
  static const vehicle = TranslatableString(
    en: 'Vehicle (optional)',
    ar: 'المركبة (اختيارية)',
    ur: 'گاڑی (اختیاری)',
    hi: 'वाहन (वैकल्पिक)',
  );
  static const approved = TranslatableString(
    en: 'Approved',
    ar: 'معتمد',
    ur: 'منظور شدہ',
    hi: 'स्वीकृत',
  );
  static const goodReceived = TranslatableString(
    en: 'Good received',
    ar: 'المستلم السليم',
    ur: 'درست وصول شدہ',
    hi: 'अच्छी तरह प्राप्त',
  );
  static const inTransit = TranslatableString(
    en: 'In transit',
    ar: 'قيد النقل',
    ur: 'راستے میں',
    hi: 'पारगमन में',
  );
  static const stillNeeded = TranslatableString(
    en: 'Still needed',
    ar: 'ما زال مطلوباً',
    ur: 'اب بھی درکار',
    hi: 'अभी भी आवश्यक',
  );
  static const dispatchQuantity = TranslatableString(
    en: 'Dispatch now',
    ar: 'الكمية المراد إرسالها',
    ur: 'ابھی ڈسپیچ کی مقدار',
    hi: 'अब भेजने की मात्रा',
  );
  static const dispatchHistory = TranslatableString(
    en: 'Dispatch history',
    ar: 'سجل الإرسال',
    ur: 'ڈسپیچ کی تاریخ',
    hi: 'डिस्पैच इतिहास',
  );
  static const receiptReview = TranslatableString(
    en: 'Receipt review',
    ar: 'مراجعة الاستلام',
    ur: 'وصولی کا جائزہ',
    hi: 'प्राप्ति समीक्षा',
  );
  static const reviewDelivery = TranslatableString(
    en: 'Review Delivery',
    ar: 'مراجعة التسليم',
    ur: 'ڈیلیوری کا جائزہ',
    hi: 'डिलीवरी की समीक्षा',
  );
  static const receiveAllAsDispatched = TranslatableString(
    en: 'Receive all as dispatched',
    ar: 'استلام الكل كما تم إرساله',
    ur: 'تمام کو ڈسپیچ کے مطابق وصول کریں',
    hi: 'सभी को भेजी गई मात्रा के रूप में प्राप्त करें',
  );
  static const reviewed = TranslatableString(
    en: 'Reviewed',
    ar: 'تمت المراجعة',
    ur: 'جائزہ مکمل',
    hi: 'समीक्षित',
  );
  static const pending = TranslatableString(
    en: 'Pending',
    ar: 'قيد الانتظار',
    ur: 'زیر التوا',
    hi: 'लंबित',
  );
  static const deliveryException = TranslatableString(
    en: 'Delivery Exception',
    ar: 'استثناء التسليم',
    ur: 'ڈیلیوری استثناء',
    hi: 'डिलीवरी अपवाद',
  );
  static const result = TranslatableString(
    en: 'Result',
    ar: 'النتيجة',
    ur: 'نتیجہ',
    hi: 'परिणाम',
  );
  static const explanation = TranslatableString(
    en: 'Explanation',
    ar: 'التوضيح',
    ur: 'وضاحت',
    hi: 'स्पष्टीकरण',
  );
  static const exceptionExplanationRequired = TranslatableString(
    en: 'Required for Missing or Damaged.',
    ar: 'مطلوب في حالة النقص أو التلف.',
    ur: 'گم یا خراب ہونے کی صورت میں ضروری ہے۔',
    hi: 'लापता या क्षतिग्रस्त होने पर आवश्यक है।',
  );
  static const replacementEligible = TranslatableString(
    en: 'Replacement remains eligible',
    ar: 'يبقى الاستبدال مستحقاً',
    ur: 'متبادل کی اہلیت برقرار ہے',
    hi: 'प्रतिस्थापन योग्य रहता है',
  );
  static const saveReview = TranslatableString(
    en: 'Save Review',
    ar: 'حفظ المراجعة',
    ur: 'جائزہ محفوظ کریں',
    hi: 'समीक्षा सहेजें',
  );
  static const reviewAndMarkReceived = TranslatableString(
    en: 'Review & Mark Received',
    ar: 'مراجعة وتأكيد الاستلام',
    ur: 'جائزہ لے کر موصول شدہ نشان زد کریں',
    hi: 'समीक्षा करें और प्राप्त के रूप में चिह्नित करें',
  );
  static const reviewDeliveredMaterials = TranslatableString(
    en: 'Review delivered materials',
    ar: 'مراجعة المواد المسلّمة',
    ur: 'پہنچائے گئے مواد کا جائزہ لیں',
    hi: 'वितरित सामग्री की समीक्षा करें',
  );
  static const reviewDeliveryLineByLine = TranslatableString(
    en: 'Check every line against the physical receipt.',
    ar: 'تحقق من كل بند مقابل الاستلام الفعلي.',
    ur: 'ہر لائن کو موصول شدہ اصل مواد کے ساتھ چیک کریں۔',
    hi: 'हर पंक्ति को वास्तविक प्राप्ति के विरुद्ध जांचें।',
  );
  static const saveReceiptReview = TranslatableString(
    en: 'Save receipt review',
    ar: 'حفظ مراجعة الاستلام',
    ur: 'وصولی کا جائزہ محفوظ کریں',
    hi: 'प्राप्ति समीक्षा सहेजें',
  );
  static const confirmReceipt = TranslatableString(
    en: 'Confirm receipt review',
    ar: 'تأكيد مراجعة الاستلام',
    ur: 'وصولی کا جائزہ تصدیق کریں',
    hi: 'प्राप्ति समीक्षा की पुष्टि करें',
  );
  static const allLinesReviewed = TranslatableString(
    en: 'All dispatch lines have been reviewed.',
    ar: 'تمت مراجعة جميع بنود الإرسال.',
    ur: 'تمام ڈسپیچ لائنز کا جائزہ لیا گیا ہے۔',
    hi: 'सभी डिस्पैच पंक्तियों की समीक्षा की गई है।',
  );
  static const outcome = TranslatableString(
    en: 'Outcome',
    ar: 'النتيجة',
    ur: 'نتیجہ',
    hi: 'परिणाम',
  );
  static const goodQuantity = TranslatableString(
    en: 'Good quantity',
    ar: 'الكمية السليمة',
    ur: 'درست مقدار',
    hi: 'अच्छी मात्रा',
  );
  static const missingQuantity = TranslatableString(
    en: 'Missing quantity',
    ar: 'الكمية الناقصة',
    ur: 'گمشدہ مقدار',
    hi: 'लापता मात्रा',
  );
  static const damagedQuantity = TranslatableString(
    en: 'Damaged quantity',
    ar: 'الكمية التالفة',
    ur: 'خراب مقدار',
    hi: 'क्षतिग्रस्त मात्रा',
  );
  static const note = TranslatableString(
    en: 'Note',
    ar: 'ملاحظة',
    ur: 'نوٹ',
    hi: 'नोट',
  );
  static const exceptionNote = TranslatableString(
    en: 'Line note (required for missing or damaged)',
    ar: 'ملاحظة البند (مطلوبة للنقص أو التلف)',
    ur: 'لائن نوٹ (گم یا خراب ہونے پر ضروری)',
    hi: 'लाइन नोट (लापता या क्षतिग्रस्त होने पर आवश्यक)',
  );
  static const noDispatch = TranslatableString(
    en: 'No committed dispatches yet.',
    ar: 'لا توجد عمليات إرسال معتمدة حتى الآن.',
    ur: 'ابھی تک کوئی تصدیق شدہ ڈسپیچ نہیں۔',
    hi: 'अभी तक कोई प्रतिबद्ध डिस्पैच नहीं।',
  );
  static const savingFailed = TranslatableString(
    en: 'This operation could not be saved. Refresh and review the current state.',
    ar: 'تعذر حفظ العملية. حدّث وراجع الحالة الحالية.',
    ur: 'یہ عمل محفوظ نہیں ہو سکا۔ ریفریش کریں اور موجودہ حالت دیکھیں۔',
    hi: 'यह कार्रवाई सहेजी नहीं जा सकी। रीफ्रेश करके वर्तमान स्थिति देखें।',
  );
  static const invalidDispatch = TranslatableString(
    en: 'Enter a positive quantity for at least one line.',
    ar: 'أدخل كمية موجبة لبند واحد على الأقل.',
    ur: 'کم از کم ایک لائن کے لیے مثبت مقدار درج کریں۔',
    hi: 'कम से कम एक पंक्ति के लिए धनात्मक मात्रा दर्ज करें।',
  );
  static const invalidReceipt = TranslatableString(
    en: 'Review every line. Good, missing and damaged quantities must equal the dispatched quantity; exceptions need a note.',
    ar: 'راجع كل بند. يجب أن يساوي مجموع الكميات السليمة والناقصة والتالفة الكمية المرسلة، وتتطلب الاستثناءات ملاحظة.',
    ur: 'ہر لائن کا جائزہ لیں۔ درست، گمشدہ اور خراب مقدار کا مجموعہ ڈسپیچ مقدار کے برابر ہونا چاہیے؛ استثناء کے لیے نوٹ ضروری ہے۔',
    hi: 'हर पंक्ति की समीक्षा करें। अच्छी, लापता और क्षतिग्रस्त मात्रा का योग भेजी गई मात्रा के बराबर होना चाहिए; अपवादों के लिए नोट आवश्यक है।',
  );
  static const deliveryOrdersAndReturns = TranslatableString(
    en: 'Delivery Orders and returns',
    ar: 'أوامر التسليم والمرتجعات',
    ur: 'ڈیلیوری آرڈرز اور واپسی',
    hi: 'डिलीवरी ऑर्डर और वापसी',
  );
  static const deliveryOrders = TranslatableString(
    en: 'Delivery Orders',
    ar: 'أوامر التسليم',
    ur: 'ڈیلیوری آرڈرز',
    hi: 'डिलीवरी ऑर्डर',
  );
  static const deliveryOrder = TranslatableString(
    en: 'Delivery Order',
    ar: 'أمر التسليم',
    ur: 'ڈیلیوری آرڈر',
    hi: 'डिलीवरी ऑर्डर',
  );
  static const deliveryOrderReference = TranslatableString(
    en: 'Delivery Order reference',
    ar: 'مرجع أمر التسليم',
    ur: 'ڈیلیوری آرڈر حوالہ',
    hi: 'डिलीवरी ऑर्डर संदर्भ',
  );
  static const automaticDeliveryNumber = TranslatableString(
    en: 'Delivery number assigned automatically',
    ar: 'يتم تعيين رقم التسليم تلقائيًا',
    ur: 'ڈیلیوری نمبر خود بخود دیا جائے گا',
    hi: 'डिलीवरी नंबर अपने आप दिया जाएगा',
  );
  static const automaticDeliveryNumberHelp = TranslatableString(
    en: 'Generate once. The same number is used for every print, download and revision.',
    ar: 'أنشئه مرة واحدة. يُستخدم الرقم نفسه لكل طباعة وتنزيل ومراجعة.',
    ur: 'ایک بار بنائیں۔ ہر پرنٹ، ڈاؤن لوڈ اور نظرثانی میں یہی نمبر استعمال ہوگا۔',
    hi: 'एक बार बनाएं। हर प्रिंट, डाउनलोड और संशोधन में वही नंबर उपयोग होगा।',
  );
  static const reusedDeliveryNumberHelp = TranslatableString(
    en: 'This delivery number is kept for every print, download and revision.',
    ar: 'يُحفظ رقم التسليم هذا لكل طباعة وتنزيل ومراجعة.',
    ur: 'یہ ڈیلیوری نمبر ہر پرنٹ، ڈاؤن لوڈ اور نظرثانی میں برقرار رہتا ہے۔',
    hi: 'यह डिलीवरी नंबर हर प्रिंट, डाउनलोड और संशोधन में बना रहता है।',
  );
  static const deliveryOrderReferenceRequired = TranslatableString(
    en: 'Enter the official Delivery Order reference.',
    ar: 'أدخل مرجع أمر التسليم الرسمي.',
    ur: 'سرکاری ڈیلیوری آرڈر حوالہ درج کریں۔',
    hi: 'आधिकारिक डिलीवरी ऑर्डर संदर्भ दर्ज करें।',
  );
  static const deliveryOrderAfterReceipt = TranslatableString(
    en: 'Dispatch evidence remains immutable. A confirmed receipt review creates the current Delivery Report with good quantities.',
    ar: 'يبقى إثبات الإرسال غير قابل للتعديل. تنشئ مراجعة الاستلام المؤكدة تقرير التسليم الحالي بالكميات السليمة.',
    ur: 'ڈسپیچ کا ثبوت ناقابلِ ترمیم رہتا ہے۔ تصدیق شدہ رسید جائزہ اچھی مقدار کے ساتھ موجودہ ڈیلیوری رپورٹ بناتا ہے۔',
    hi: 'डिस्पैच प्रमाण अपरिवर्तनीय रहता है। पुष्ट रसीद समीक्षा अच्छी मात्राओं के साथ वर्तमान डिलीवरी रिपोर्ट बनाती है।',
  );
  static const generateDeliveryOrder = TranslatableString(
    en: 'Generate Delivery Order',
    ar: 'إنشاء أمر التسليم',
    ur: 'ڈیلیوری آرڈر بنائیں',
    hi: 'डिलीवरी ऑर्डर बनाएं',
  );
  static const regenerateDeliveryOrder = TranslatableString(
    en: 'Create new revision',
    ar: 'إنشاء مراجعة جديدة',
    ur: 'نیا ورژن بنائیں',
    hi: 'नया संशोधन बनाएं',
  );
  static const revision = TranslatableString(
    en: 'Revision',
    ar: 'المراجعة',
    ur: 'ورژن',
    hi: 'संशोधन',
  );
  static const noDeliveryOrders = TranslatableString(
    en: 'No committed dispatches are available yet.',
    ar: 'لا توجد عمليات إرسال معتمدة حتى الآن.',
    ur: 'ابھی تک کوئی تصدیق شدہ ڈسپیچ دستیاب نہیں ہے۔',
    hi: 'अभी तक कोई पुष्ट डिस्पैच उपलब्ध नहीं है।',
  );
  static const exportExcel = TranslatableString(
    en: 'Excel',
    ar: 'إكسل',
    ur: 'ایکسل',
    hi: 'एक्सेल',
  );
  static const printDocument = TranslatableString(
    en: 'Print / PDF',
    ar: 'طباعة / PDF',
    ur: 'پرنٹ / PDF',
    hi: 'प्रिंट / PDF',
  );
  static const downloadPdf = TranslatableString(
    en: 'Download PDF',
    ar: 'تنزيل PDF',
    ur: 'PDF ڈاؤن لوڈ کریں',
    hi: 'PDF डाउनलोड करें',
  );
  static const share = TranslatableString(
    en: 'Share',
    ar: 'مشاركة',
    ur: 'شیئر کریں',
    hi: 'साझा करें',
  );
  static const storeVersion = TranslatableString(
    en: 'Store Version',
    ar: 'حفظ الإصدار',
    ur: 'ورژن محفوظ کریں',
    hi: 'संस्करण संग्रहीत करें',
  );
  static const materialReturns = TranslatableString(
    en: 'Material returns',
    ar: 'مرتجعات المواد',
    ur: 'میٹریل واپسی',
    hi: 'सामग्री वापसी',
  );
  static const newMaterialReturn = TranslatableString(
    en: 'New Material Return',
    ar: 'إرجاع مواد جديد',
    ur: 'نئی میٹریل واپسی',
    hi: 'नई सामग्री वापसी',
  );
  static const selectDeliveredMaterial = TranslatableString(
    en: 'Select delivered material',
    ar: 'اختر المواد المسلّمة',
    ur: 'ڈیلیور شدہ میٹریل منتخب کریں',
    hi: 'वितरित सामग्री चुनें',
  );
  static const eligibleGoodReceivedOnly = TranslatableString(
    en: 'Only eligible good-received quantities from this project scope are shown.',
    ar: 'تظهر فقط الكميات السليمة المستلمة والمؤهلة من نطاق المشروع هذا.',
    ur: 'اس پروجیکٹ دائرے سے صرف اہل درست وصول شدہ مقدار دکھائی جاتی ہے۔',
    hi: 'इस परियोजना दायरे से केवल योग्य अच्छी प्राप्त मात्राएँ दिखाई जाती हैं।',
  );
  static const searchDeliveredItems = TranslatableString(
    en: 'Search delivered items',
    ar: 'البحث في المواد المسلّمة',
    ur: 'ڈیلیور شدہ اشیاء تلاش کریں',
    hi: 'वितरित सामग्री खोजें',
  );
  static const searchItemHint = TranslatableString(
    en: 'Type item name',
    ar: 'اكتب اسم الصنف',
    ur: 'آئٹم کا نام لکھیں',
    hi: 'वस्तु का नाम लिखें',
  );
  static const reviewReturn = TranslatableString(
    en: 'Review Return',
    ar: 'مراجعة الإرجاع',
    ur: 'واپسی کا جائزہ',
    hi: 'वापसी की समीक्षा',
  );
  static const returnDraft = TranslatableString(
    en: 'Return Draft',
    ar: 'مسودة الإرجاع',
    ur: 'واپسی ڈرافٹ',
    hi: 'वापसी ड्राफ़्ट',
  );
  static const reviewReturnedMaterial = TranslatableString(
    en: 'Review returned material',
    ar: 'مراجعة المواد المرتجعة',
    ur: 'واپس کیے گئے میٹریل کا جائزہ',
    hi: 'लौटाई गई सामग्री की समीक्षा',
  );
  static const procurementConfirmsBeforeStock = TranslatableString(
    en: 'Procurement confirms receipt before stock is restored.',
    ar: 'تؤكد المشتريات الاستلام قبل إعادة المخزون.',
    ur: 'اسٹاک بحال ہونے سے پہلے پروکیورمنٹ وصولی کی تصدیق کرتی ہے۔',
    hi: 'स्टॉक बहाल होने से पहले खरीद विभाग प्राप्ति की पुष्टि करता है।',
  );
  static const notes = TranslatableString(
    en: 'Notes',
    ar: 'ملاحظات',
    ur: 'نوٹس',
    hi: 'टिप्पणियाँ',
  );
  static const eligibleToReturn = TranslatableString(
    en: 'Eligible to return',
    ar: 'المتاح للإرجاع',
    ur: 'واپسی کے لیے اہل',
    hi: 'वापसी के लिए योग्य',
  );
  static const returnQuantity = TranslatableString(
    en: 'Return quantity',
    ar: 'كمية الإرجاع',
    ur: 'واپسی کی مقدار',
    hi: 'वापसी मात्रा',
  );
  static const returnNote = TranslatableString(
    en: 'Return note (optional)',
    ar: 'ملاحظة الإرجاع (اختيارية)',
    ur: 'واپسی نوٹ (اختیاری)',
    hi: 'वापसी नोट (वैकल्पिक)',
  );
  static const saveReturnDraft = TranslatableString(
    en: 'Save return draft',
    ar: 'حفظ مسودة الإرجاع',
    ur: 'واپسی ڈرافٹ محفوظ کریں',
    hi: 'वापसी ड्राफ़्ट सहेजें',
  );
  static const submitReturn = TranslatableString(
    en: 'Submit return',
    ar: 'إرسال الإرجاع',
    ur: 'واپسی جمع کرائیں',
    hi: 'वापसी जमा करें',
  );
  static const confirmReturn = TranslatableString(
    en: 'Confirm warehouse return',
    ar: 'تأكيد إرجاع المستودع',
    ur: 'گودام واپسی کی تصدیق کریں',
    hi: 'वेयरहाउस वापसी की पुष्टि करें',
  );
  static const rejectReturn = TranslatableString(
    en: 'Reject return',
    ar: 'رفض الإرجاع',
    ur: 'واپسی مسترد کریں',
    hi: 'वापसी अस्वीकार करें',
  );
  static const rejectionReason = TranslatableString(
    en: 'Rejection reason',
    ar: 'سبب الرفض',
    ur: 'مسترد کرنے کی وجہ',
    hi: 'अस्वीकृति का कारण',
  );
  static const newInventoryItem = TranslatableString(
    en: 'Create identified inventory item',
    ar: 'إنشاء صنف مخزون محدد',
    ur: 'شناخت شدہ انوینٹری آئٹم بنائیں',
    hi: 'पहचानी गई इन्वेंटरी वस्तु बनाएं',
  );
  static const mapInventoryItem = TranslatableString(
    en: 'Map to inventory item',
    ar: 'ربط بصنف المخزون',
    ur: 'انوینٹری آئٹم سے منسلک کریں',
    hi: 'इन्वेंटरी आइटम से जोड़ें',
  );
  static const noEligibleReturns = TranslatableString(
    en: 'No good received quantity is currently eligible for return.',
    ar: 'لا توجد كمية مستلمة سليمة متاحة للإرجاع حالياً.',
    ur: 'اس وقت کوئی درست وصول شدہ مقدار واپسی کے لیے اہل نہیں ہے۔',
    hi: 'वर्तमान में वापसी के लिए कोई अच्छी प्राप्त मात्रा योग्य नहीं है।',
  );
  static const noMaterialReturns = TranslatableString(
    en: 'No material returns have been prepared.',
    ar: 'لم يتم إعداد أي مرتجعات مواد.',
    ur: 'ابھی کوئی میٹریل واپسی تیار نہیں کی گئی۔',
    hi: 'अभी तक कोई सामग्री वापसी तैयार नहीं की गई है।',
  );
  static const invalidReturn = TranslatableString(
    en: 'Enter a positive quantity that does not exceed the eligible amount.',
    ar: 'أدخل كمية موجبة لا تتجاوز الكمية المتاحة.',
    ur: 'مثبت مقدار درج کریں جو اہل مقدار سے زیادہ نہ ہو۔',
    hi: 'ऐसी धनात्मक मात्रा दर्ज करें जो योग्य राशि से अधिक न हो।',
  );

  static TranslatableString dispatchUnits(String quantity) =>
      TranslatableString(
        en: 'Dispatch $quantity Units',
        ar: 'إرسال $quantity وحدة',
        ur: '$quantity یونٹس ڈسپیچ کریں',
        hi: '$quantity इकाइयाँ भेजें',
      );

  static TranslatableString linesReviewed(int reviewed, int total) =>
      TranslatableString(
        en: '$reviewed / $total lines reviewed',
        ar: 'تمت مراجعة $reviewed من $total بنداً',
        ur: '$reviewed / $total لائنز کا جائزہ',
        hi: '$reviewed / $total पंक्तियाँ समीक्षित',
      );

  static TranslatableString replacementQuantity(
    String quantity,
    String unit,
  ) => TranslatableString(
    en: 'The $quantity $unit exception stays outstanding for a later dispatch.',
    ar: 'تبقى كمية الاستثناء $quantity $unit معلقة لإرسال لاحق.',
    ur: '$quantity $unit استثنائی مقدار بعد کے ڈسپیچ کے لیے باقی رہتی ہے۔',
    hi: '$quantity $unit अपवाद मात्रा बाद के डिस्पैच के लिए लंबित रहती है।',
  );

  static TranslatableString nextItems(int count) => TranslatableString(
    en: 'Next · $count Items',
    ar: 'التالي · $count أصناف',
    ur: 'اگلا · $count آئٹمز',
    hi: 'अगला · $count वस्तुएँ',
  );

  static TranslatableString selectedItems(int count) => TranslatableString(
    en: '$count ${count == 1 ? 'item' : 'items'} selected',
    ar: 'تم اختيار $count ${count == 1 ? 'صنف' : 'أصناف'}',
    ur: '$count آئٹمز منتخب',
    hi: '$count वस्तुएँ चुनी गईं',
  );
}

/// The approved four-column Delivery Report keeps technical metadata inside
/// Description. Size is always stated explicitly; model follows when frozen
/// on the submitted Material Request line.
String yorksV1DeliveryOrderLineMetadata(YorksV1DeliveryOrderLine line) {
  final size = line.size?.trim();
  final model = line.model?.trim();
  return [
    '${YorksV1LogisticsStrings.itemSize.primary}: ${size == null || size.isEmpty ? YorksV1LogisticsStrings.notProvided.primary : size}',
    if (model != null && model.isNotEmpty)
      '${YorksV1LogisticsStrings.itemModel.primary}: $model',
  ].join(' · ');
}

String yorksV1DeliveryOrderLineDescription(YorksV1DeliveryOrderLine line) =>
    '${line.description}\n${yorksV1DeliveryOrderLineMetadata(line)}';

TranslatableString yorksV1LogisticsSourceCopy(YorksV1LogisticsSource source) =>
    switch (source) {
      YorksV1LogisticsSource.warehouse => const TranslatableString(
        en: 'Warehouse',
        ar: 'المستودع',
        ur: 'گودام',
        hi: 'वेयरहाउस',
      ),
      YorksV1LogisticsSource.externalSupplier => const TranslatableString(
        en: 'External supplier',
        ar: 'مورد خارجي',
        ur: 'بیرونی سپلائر',
        hi: 'बाहरी आपूर्तिकर्ता',
      ),
    };

TranslatableString yorksV1DispatchStateCopy(YorksV1DispatchState state) =>
    switch (state) {
      YorksV1DispatchState.receiptPending => const TranslatableString(
        en: 'Receipt review required',
        ar: 'مراجعة الاستلام مطلوبة',
        ur: 'وصولی کا جائزہ درکار',
        hi: 'प्राप्ति समीक्षा आवश्यक',
      ),
      YorksV1DispatchState.partiallyReceived => const TranslatableString(
        en: 'Partially received',
        ar: 'مستلم جزئياً',
        ur: 'جزوی وصولی',
        hi: 'आंशिक रूप से प्राप्त',
      ),
      YorksV1DispatchState.received => const TranslatableString(
        en: 'Received',
        ar: 'تم الاستلام',
        ur: 'وصول شدہ',
        hi: 'प्राप्त',
      ),
    };

TranslatableString yorksV1ReceiptOutcomeCopy(YorksV1ReceiptOutcome outcome) =>
    switch (outcome) {
      YorksV1ReceiptOutcome.received => const TranslatableString(
        en: 'Received',
        ar: 'مستلم',
        ur: 'وصول شدہ',
        hi: 'प्राप्त',
      ),
      YorksV1ReceiptOutcome.missing => const TranslatableString(
        en: 'Missing',
        ar: 'ناقص',
        ur: 'گمشدہ',
        hi: 'लापता',
      ),
      YorksV1ReceiptOutcome.damaged => const TranslatableString(
        en: 'Damaged',
        ar: 'تالف',
        ur: 'خراب',
        hi: 'क्षतिग्रस्त',
      ),
      YorksV1ReceiptOutcome.mixed => const TranslatableString(
        en: 'Mixed',
        ar: 'مختلط',
        ur: 'مخلوط',
        hi: 'मिश्रित',
      ),
    };

TranslatableString yorksV1MaterialReturnStateCopy(
  YorksV1MaterialReturnState state,
) => switch (state) {
  YorksV1MaterialReturnState.draft => const TranslatableString(
    en: 'Draft',
    ar: 'مسودة',
    ur: 'ڈرافٹ',
    hi: 'ड्राफ़्ट',
  ),
  YorksV1MaterialReturnState.submitted => const TranslatableString(
    en: 'Submitted',
    ar: 'مرسل',
    ur: 'جمع شدہ',
    hi: 'जमा किया गया',
  ),
  YorksV1MaterialReturnState.awaitingApproval => const TranslatableString(
    en: 'Awaiting approval',
    ar: 'بانتظار الاعتماد',
    ur: 'منظوری کا منتظر',
    hi: 'स्वीकृति की प्रतीक्षा',
  ),
  YorksV1MaterialReturnState.returnedForChanges => const TranslatableString(
    en: 'Returned for changes',
    ar: 'معاد للتعديل',
    ur: 'تبدیلیوں کے لیے واپس',
    hi: 'बदलाव के लिए वापस',
  ),
  YorksV1MaterialReturnState.approved => const TranslatableString(
    en: 'Approved',
    ar: 'معتمد',
    ur: 'منظور شدہ',
    hi: 'स्वीकृत',
  ),
  YorksV1MaterialReturnState.dispatched => const TranslatableString(
    en: 'Dispatched to warehouse',
    ar: 'مرسل إلى المستودع',
    ur: 'گودام بھیج دیا گیا',
    hi: 'गोदाम भेजा गया',
  ),
  YorksV1MaterialReturnState.confirmed => const TranslatableString(
    en: 'Confirmed',
    ar: 'مؤكد',
    ur: 'تصدیق شدہ',
    hi: 'पुष्ट',
  ),
  YorksV1MaterialReturnState.rejected => const TranslatableString(
    en: 'Rejected',
    ar: 'مرفوض',
    ur: 'مسترد',
    hi: 'अस्वीकृत',
  ),
  YorksV1MaterialReturnState.cancelled => const TranslatableString(
    en: 'Cancelled',
    ar: 'ملغى',
    ur: 'منسوخ',
    hi: 'रद्द',
  ),
};
