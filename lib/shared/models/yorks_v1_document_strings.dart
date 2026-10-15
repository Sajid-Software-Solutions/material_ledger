import 'app_strings.dart';
import 'yorks_v1_document.dart';

abstract final class YorksV1DocumentStrings {
  static const documents = TranslatableString(
    en: 'Documents',
    ar: 'المستندات',
    ur: 'دستاویزات',
    hi: 'दस्तावेज़',
  );
  static const documentsDescription = TranslatableString(
    en: 'Controlled versions, authorized links and server activity.',
    ar: 'إصدارات مضبوطة وروابط مصرح بها ونشاط خادم.',
    ur: 'کنٹرول شدہ ورژنز، مجاز روابط اور سرور سرگرمی۔',
    hi: 'नियंत्रित संस्करण, अधिकृत लिंक और सर्वर गतिविधि।',
  );
  static const addDocument = TranslatableString(
    en: 'Add document',
    ar: 'إضافة مستند',
    ur: 'دستاویز شامل کریں',
    hi: 'दस्तावेज़ जोड़ें',
  );
  static const dropDocuments = TranslatableString(
    en: 'Drop documents here',
    ar: 'أفلت المستندات هنا',
    ur: 'دستاویزات یہاں چھوڑیں',
    hi: 'दस्तावेज़ यहाँ छोड़ें',
  );
  static const dropDocumentsActive = TranslatableString(
    en: 'Release to add documents',
    ar: 'أفلت لإضافة المستندات',
    ur: 'دستاویزات شامل کرنے کے لیے چھوڑیں',
    hi: 'दस्तावेज़ जोड़ने के लिए छोड़ें',
  );
  static const dropDocumentsPrompt = TranslatableString(
    en: 'Drag files here or choose them from your device.',
    ar: 'اسحب الملفات هنا أو اخترها من جهازك.',
    ur: 'فائلیں یہاں گھسیٹیں یا اپنے آلے سے منتخب کریں۔',
    hi: 'फ़ाइलें यहाँ खींचें या अपने डिवाइस से चुनें।',
  );
  static const linkExistingDocument = TranslatableString(
    en: 'Link existing document',
    ar: 'ربط مستند موجود',
    ur: 'موجودہ دستاویز لنک کریں',
    hi: 'मौजूदा दस्तावेज़ लिंक करें',
  );
  static const uploadDocument = TranslatableString(
    en: 'Upload controlled version',
    ar: 'رفع نسخة مضبوطة',
    ur: 'کنٹرول شدہ ورژن اپ لوڈ کریں',
    hi: 'नियंत्रित संस्करण अपलोड करें',
  );
  static const linkDocument = TranslatableString(
    en: 'Link document',
    ar: 'ربط المستند',
    ur: 'دستاویز لنک کریں',
    hi: 'दस्तावेज़ लिंक करें',
  );
  static const removeLink = TranslatableString(
    en: 'Remove link',
    ar: 'إزالة الرابط',
    ur: 'لنک ہٹائیں',
    hi: 'लिंक हटाएं',
  );
  static const removalReason = TranslatableString(
    en: 'Removal reason',
    ar: 'سبب الإزالة',
    ur: 'ہٹانے کی وجہ',
    hi: 'हटाने का कारण',
  );
  static const activity = TranslatableString(
    en: 'Activity',
    ar: 'النشاط',
    ur: 'سرگرمی',
    hi: 'गतिविधि',
  );
  static const noDocuments = TranslatableString(
    en: 'No authorized documents yet.',
    ar: 'لا توجد مستندات مصرح بها بعد.',
    ur: 'ابھی کوئی مجاز دستاویز نہیں۔',
    hi: 'अभी कोई अधिकृत दस्तावेज़ नहीं है।',
  );
  static const version = TranslatableString(
    en: 'Version',
    ar: 'الإصدار',
    ur: 'ورژن',
    hi: 'संस्करण',
  );
  static const revision = TranslatableString(
    en: 'Revision',
    ar: 'المراجعة',
    ur: 'نظر ثانی',
    hi: 'संशोधन',
  );
  static const classification = TranslatableString(
    en: 'Classification',
    ar: 'التصنيف',
    ur: 'درجہ بندی',
    hi: 'वर्गीकरण',
  );
  static const operational = TranslatableString(
    en: 'Operational',
    ar: 'تشغيلي',
    ur: 'عملیاتی',
    hi: 'परिचालन',
  );
  static const commercial = TranslatableString(
    en: 'Commercial',
    ar: 'تجاري',
    ur: 'تجارتی',
    hi: 'वाणिज्यिक',
  );
  static const adminRestricted = TranslatableString(
    en: 'Admin restricted',
    ar: 'مقيد للمسؤول',
    ur: 'ایڈمن کے لیے محدود',
    hi: 'केवल व्यवस्थापक',
  );
  static const uploadFailed = TranslatableString(
    en: 'The document could not be uploaded.',
    ar: 'تعذر رفع المستند.',
    ur: 'دستاویز اپ لوڈ نہیں ہو سکی۔',
    hi: 'दस्तावेज़ अपलोड नहीं हो सका।',
  );
  static const uploadSucceeded = TranslatableString(
    en: 'Controlled document version uploaded.',
    ar: 'تم رفع نسخة المستند المضبوطة.',
    ur: 'کنٹرول شدہ دستاویز ورژن اپ لوڈ ہو گیا۔',
    hi: 'नियंत्रित दस्तावेज़ संस्करण अपलोड हो गया।',
  );
  static const uploadConfirmedRefreshPending = TranslatableString(
    en: 'Upload confirmed. The document list could not be refreshed.',
    ar: 'تم تأكيد الرفع. تعذر تحديث قائمة المستندات.',
    ur: 'اپ لوڈ کی تصدیق ہو گئی۔ دستاویزات کی فہرست تازہ نہیں ہو سکی۔',
    hi: 'अपलोड की पुष्टि हुई। दस्तावेज़ सूची ताज़ा नहीं हो सकी।',
  );
  static const uploadInProgress = TranslatableString(
    en: 'Uploading and checking the document…',
    ar: 'جارٍ رفع المستند والتحقق منه…',
    ur: 'دستاویز اپ لوڈ اور چیک ہو رہی ہے…',
    hi: 'दस्तावेज़ अपलोड और जाँच हो रही है…',
  );
  static const uploadOutcomeUnknown = TranslatableString(
    en: 'Upload not confirmed yet. Reselect the same file to check and continue safely.',
    ar: 'لم يتم تأكيد الرفع بعد. أعد تحديد الملف نفسه للتحقق والمتابعة بأمان.',
    ur: 'اپ لوڈ کی تصدیق ابھی نہیں ہوئی۔ محفوظ طور پر جانچنے اور جاری رکھنے کے لیے وہی فائل دوبارہ منتخب کریں۔',
    hi: 'अपलोड की पुष्टि अभी नहीं हुई। सुरक्षित जाँच और आगे बढ़ने के लिए वही फ़ाइल फिर चुनें।',
  );
  static const uploadNotSent = TranslatableString(
    en: 'Upload did not start. This attempt did not send the file.',
    ar: 'لم يبدأ الرفع. لم ترسل هذه المحاولة الملف.',
    ur: 'اپ لوڈ شروع نہیں ہوا۔ اس کوشش میں فائل نہیں بھیجی گئی۔',
    hi: 'अपलोड शुरू नहीं हुआ। इस प्रयास में फ़ाइल नहीं भेजी गई।',
  );
  static const reselectUpload = TranslatableString(
    en: 'Reselect file',
    ar: 'إعادة تحديد الملف',
    ur: 'فائل دوبارہ منتخب کریں',
    hi: 'फ़ाइल फिर चुनें',
  );
  static const uploadFileMismatch = TranslatableString(
    en: 'Select the original file with the same name and contents.',
    ar: 'حدد الملف الأصلي بنفس الاسم والمحتوى.',
    ur: 'اسی نام اور مواد والی اصل فائل منتخب کریں۔',
    hi: 'उसी नाम और सामग्री वाली मूल फ़ाइल चुनें।',
  );
  static const uploadVersion = TranslatableString(
    en: 'Upload new version',
    ar: 'رفع إصدار جديد',
    ur: 'نیا ورژن اپ لوڈ کریں',
    hi: 'नया संस्करण अपलोड करें',
  );
  static const storeControlledVersion = TranslatableString(
    en: 'Store controlled version',
    ar: 'حفظ نسخة مضبوطة',
    ur: 'کنٹرول شدہ ورژن محفوظ کریں',
    hi: 'नियंत्रित संस्करण सहेजें',
  );
  static const download = TranslatableString(
    en: 'Download',
    ar: 'تنزيل',
    ur: 'ڈاؤن لوڈ',
    hi: 'डाउनलोड',
  );
  static const downloadFailed = TranslatableString(
    en: 'The document could not be downloaded.',
    ar: 'تعذر تنزيل المستند.',
    ur: 'دستاویز ڈاؤن لوڈ نہیں ہو سکی۔',
    hi: 'दस्तावेज़ डाउनलोड नहीं हो सका।',
  );
  static const documentLinked = TranslatableString(
    en: 'Document linked to this record.',
    ar: 'تم ربط المستند بهذا السجل.',
    ur: 'دستاویز اس ریکارڈ سے لنک ہو گئی۔',
    hi: 'दस्तावेज़ इस रिकॉर्ड से लिंक हो गया।',
  );
  static const linkFailed = TranslatableString(
    en: 'The document could not be linked.',
    ar: 'تعذر ربط المستند.',
    ur: 'دستاویز لنک نہیں ہو سکی۔',
    hi: 'दस्तावेज़ लिंक نہیں ہو سکا۔',
  );
  static const linkRemoved = TranslatableString(
    en: 'Document link removed.',
    ar: 'تمت إزالة رابط المستند.',
    ur: 'دستاویز لنک ہٹا دیا گیا۔',
    hi: 'दस्तावेज़ लिंक हटा दिया गया।',
  );
  static const removeFailed = TranslatableString(
    en: 'The document link could not be removed.',
    ar: 'تعذر إزالة رابط المستند.',
    ur: 'دستاویز لنک ہٹایا نہیں جا سکا۔',
    hi: 'दस्तावेज़ लिंक हटाया नहीं जा सका।',
  );
  static const linkedTo = TranslatableString(
    en: 'Linked to',
    ar: 'مرتبط بـ',
    ur: 'اس سے منسلک',
    hi: 'इससे लिंक है',
  );
  static const currentVersion = TranslatableString(
    en: 'Current controlled version',
    ar: 'الإصدار المضبوط الحالي',
    ur: 'موجودہ کنٹرول شدہ ورژن',
    hi: 'वर्तमान नियंत्रित संस्करण',
  );
  static const selectClassification = TranslatableString(
    en: 'Select classification',
    ar: 'اختر التصنيف',
    ur: 'درجہ بندی منتخب کریں',
    hi: 'वर्गीकरण चुनें',
  );
  static const confirm = TranslatableString(
    en: 'Continue',
    ar: 'متابعة',
    ur: 'جاری رکھیں',
    hi: 'जारी रखें',
  );
  static const cancel = TranslatableString(
    en: 'Cancel',
    ar: 'إلغاء',
    ur: 'منسوخ کریں',
    hi: 'रद्द करें',
  );
  static const retry = TranslatableString(
    en: 'Retry',
    ar: 'إعادة المحاولة',
    ur: 'دوبارہ کوشش کریں',
    hi: 'फिर कोशिश करें',
  );
  static const actor = TranslatableString(
    en: 'Actor',
    ar: 'المنفذ',
    ur: 'عمل کرنے والا',
    hi: 'कर्ता',
  );
  static const entity = TranslatableString(
    en: 'Linked record',
    ar: 'السجل المرتبط',
    ur: 'منسلک ریکارڈ',
    hi: 'लिंक रिकॉर्ड',
  );
  static const fileTypes = TranslatableString(
    en: 'PDF, Excel, Word or image — up to 6 MB.',
    ar: 'PDF أو Excel أو Word أو صورة — حتى 6 ميجابايت.',
    ur: 'PDF، ایکسل، ورڈ یا تصویر — 6 MB تک۔',
    hi: 'PDF, Excel, Word या छवि — 6 MB तक।',
  );
  static const auditSafeNotice = TranslatableString(
    en: 'Activity shows server-generated event details only.',
    ar: 'يعرض النشاط تفاصيل الأحداث التي أنشأها الخادم فقط.',
    ur: 'سرگرمی صرف سرور کی تیار کردہ ایونٹ تفصیلات دکھاتی ہے۔',
    hi: 'गतिविधि केवल सर्वर-निर्मित घटना विवरण दिखाती है।',
  );
}

TranslatableString yorksV1DocumentClassificationCopy(
  YorksV1DocumentClassification classification,
) => switch (classification) {
  YorksV1DocumentClassification.operational =>
    YorksV1DocumentStrings.operational,
  YorksV1DocumentClassification.commercial => YorksV1DocumentStrings.commercial,
  YorksV1DocumentClassification.adminRestricted =>
    YorksV1DocumentStrings.adminRestricted,
};

String yorksV1DocumentEntityLabel(YorksV1DocumentEntityType entityType) {
  final copy = switch (entityType) {
    YorksV1DocumentEntityType.project => const TranslatableString(
      en: 'Project',
      ar: 'المشروع',
      ur: 'پروجیکٹ',
      hi: 'परियोजना',
    ),
    YorksV1DocumentEntityType.boqGroup => const TranslatableString(
      en: 'BOQ group',
      ar: 'مجموعة BOQ',
      ur: 'BOQ گروپ',
      hi: 'BOQ समूह',
    ),
    YorksV1DocumentEntityType.materialRequest => const TranslatableString(
      en: 'Material request',
      ar: 'طلب مواد',
      ur: 'مادی درخواست',
      hi: 'सामग्री अनुरोध',
    ),
    YorksV1DocumentEntityType.dispatch => const TranslatableString(
      en: 'Dispatch',
      ar: 'إرسال',
      ur: 'ڈسپیچ',
      hi: 'डिस्पैच',
    ),
    YorksV1DocumentEntityType.receiptReview => const TranslatableString(
      en: 'Receipt review',
      ar: 'مراجعة الاستلام',
      ur: 'وصولی کا جائزہ',
      hi: 'प्राप्ति समीक्षा',
    ),
    YorksV1DocumentEntityType.materialReturn => const TranslatableString(
      en: 'Material return',
      ar: 'إرجاع المواد',
      ur: 'مواد کی واپسی',
      hi: 'सामग्री वापसी',
    ),
    YorksV1DocumentEntityType.deliveryOrder => const TranslatableString(
      en: 'Delivery order',
      ar: 'أمر التسليم',
      ur: 'ڈیلیوری آرڈر',
      hi: 'डिलीवरी ऑर्डर',
    ),
    YorksV1DocumentEntityType.rentalProperty => const TranslatableString(
      en: 'Rental property',
      ar: 'العقار المؤجر',
      ur: 'کرائے کی جائیداد',
      hi: 'किराये की संपत्ति',
    ),
    YorksV1DocumentEntityType.supplier => const TranslatableString(
      en: 'Supplier',
      ar: 'المورد',
      ur: 'سپلائر',
      hi: 'आपूर्तिकर्ता',
    ),
    YorksV1DocumentEntityType.supplierReceiptBatch => const TranslatableString(
      en: 'Supplier receipt batch',
      ar: 'دفعة استلام المورد',
      ur: 'سپلائر وصولی بیچ',
      hi: 'आपूर्तिकर्ता रसीद बैच',
    ),
    YorksV1DocumentEntityType.accountsBaselineRevision =>
      const TranslatableString(
        en: 'Contract baseline',
        ar: 'خط أساس العقد',
        ur: 'معاہدے کی بنیادی قدر',
        hi: 'अनुबंध आधाररेखा',
      ),
    YorksV1DocumentEntityType.accountsBillingProgressRevision =>
      const TranslatableString(
        en: 'Billing progress',
        ar: 'تقدم الفوترة',
        ur: 'بلنگ پیش رفت',
        hi: 'बिलिंग प्रगति',
      ),
    YorksV1DocumentEntityType.accountsClientClaim => const TranslatableString(
      en: 'Client claim',
      ar: 'مطالبة العميل',
      ur: 'کلائنٹ کلیم',
      hi: 'ग्राहक दावा',
    ),
    YorksV1DocumentEntityType.accountsClientInvoice => const TranslatableString(
      en: 'Client invoice',
      ar: 'فاتورة العميل',
      ur: 'کلائنٹ انوائس',
      hi: 'ग्राहक चालान',
    ),
    YorksV1DocumentEntityType.accountsClientCertification =>
      const TranslatableString(
        en: 'Client certification',
        ar: 'اعتماد العميل',
        ur: 'کلائنٹ سرٹیفکیشن',
        hi: 'ग्राहक प्रमाणन',
      ),
    YorksV1DocumentEntityType.accountsClientPayment => const TranslatableString(
      en: 'Client payment',
      ar: 'دفعة العميل',
      ur: 'کلائنٹ ادائیگی',
      hi: 'ग्राहक भुगतान',
    ),
    YorksV1DocumentEntityType.accountsClientPdc => const TranslatableString(
      en: 'Client PDC',
      ar: 'شيك العميل الآجل',
      ur: 'کلائنٹ پی ڈی سی',
      hi: 'ग्राहक पीडीसी',
    ),
    YorksV1DocumentEntityType.accountsSupplierBill => const TranslatableString(
      en: 'Supplier bill',
      ar: 'فاتورة المورد',
      ur: 'سپلائر بل',
      hi: 'आपूर्तिकर्ता बिल',
    ),
    YorksV1DocumentEntityType.accountsSupplierMatch => const TranslatableString(
      en: 'Supplier match',
      ar: 'مطابقة المورد',
      ur: 'سپلائر میچ',
      hi: 'आपूर्तिकर्ता मिलान',
    ),
  };
  return copy.primary;
}
