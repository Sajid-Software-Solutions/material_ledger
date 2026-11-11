import '../../../shared/models/app_strings.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';

abstract final class CompanyAnalyticsStrings {
  static const filters = TranslatableString(
    en: "Filters",
    ar: "الفلاتر",
    ur: "فلٹرز",
    hi: "फ़िल्टर",
  );
  static const applyFilters = TranslatableString(
    en: "Apply filters",
    ar: "تطبيق الفلاتر",
    ur: "فلٹر لگائیں",
    hi: "फ़िल्टर लागू करें",
  );
  static const resetFilters = TranslatableString(
    en: "Reset filters",
    ar: "إعادة ضبط الفلاتر",
    ur: "فلٹر ری سیٹ کریں",
    hi: "फ़िल्टर रीसेट करें",
  );
  static const retryProjects = TranslatableString(
    en: "Retry project list",
    ar: "إعادة تحميل المشاريع",
    ur: "پراجیکٹ فہرست دوبارہ لوڈ کریں",
    hi: "प्रोजेक्ट सूची फिर लोड करें",
  );
  static const noProperties = TranslatableString(
    en: "No properties yet",
    ar: "لا توجد عقارات بعد",
    ur: "ابھی کوئی جائیداد نہیں",
    hi: "अभी कोई संपत्ति नहीं",
  );
  static const companyDetails = TranslatableString(
    en: "Company details",
    ar: "تفاصيل الشركة",
    ur: "کمپنی کی تفصیلات",
    hi: "कंपनी का विवरण",
  );
  static const projectsAttention = TranslatableString(
    en: "Projects needing attention",
    ar: "مشاريع تحتاج إلى اهتمام",
    ur: "توجہ طلب پراجیکٹس",
    hi: "ध्यान देने योग्य प्रोजेक्ट",
  );
  static const updated = TranslatableString(
    en: "Updated",
    ar: "تم التحديث",
    ur: "تازہ کاری",
    hi: "अपडेट",
  );
  static const snapshot = TranslatableString(
    en: "Current position",
    ar: "الوضع الحالي",
    ur: "موجودہ صورتحال",
    hi: "वर्तमान स्थिति",
  );
  static const monthlyComparison = TranslatableString(
    en: "Last two complete months",
    ar: "آخر شهرين مكتملين",
    ur: "آخری دو مکمل ماہ",
    hi: "पिछले दो पूरे महीने",
  );
  static const viewTable = TranslatableString(
    en: "View data table",
    ar: "عرض جدول البيانات",
    ur: "ڈیٹا ٹیبل دیکھیں",
    hi: "डेटा तालिका देखें",
  );
  static const recentActivity = TranslatableString(
    en: "Recently updated projects",
    ar: "المشاريع المحدثة مؤخراً",
    ur: "حال ہی میں اپ ڈیٹ کردہ پراجیکٹس",
    hi: "हाल में अपडेट किए गए प्रोजेक्ट",
  );
  static const registerPreview = TranslatableString(
    en: "Preview of the authorised project register",
    ar: "معاينة سجل المشاريع المصرح بها",
    ur: "مجاز پراجیکٹ رجسٹر کا پیش منظر",
    hi: "अधिकृत प्रोजेक्ट रजिस्टर का पूर्वावलोकन",
  );
  static const title = TranslatableString(
    en: 'Analytics',
    ar: 'التحليلات',
    ur: 'تجزیات',
    hi: 'विश्लेषण',
  );
  static const eyebrow = TranslatableString(
    en: 'COMPANY PERFORMANCE',
    ar: 'أداء الشركة',
    ur: 'کمپنی کی کارکردگی',
    hi: 'कंपनी प्रदर्शन',
  );
  static const description = TranslatableString(
    en: 'A read-only, server-confirmed view for understanding operations and opening the right source record.',
    ar: 'عرض للقراءة فقط ومؤكد من الخادم لفهم العمليات وفتح السجل الصحيح.',
    ur: 'آپریشنز سمجھنے اور درست اصل ریکارڈ کھولنے کے لیے صرف پڑھنے کا سرور سے تصدیق شدہ منظر۔',
    hi: 'संचालन समझने और सही स्रोत रिकॉर्ड खोलने के लिए केवल-पढ़ने योग्य, सर्वर-पुष्ट दृश्य।',
  );
  static const allProjects = TranslatableString(
    en: 'All authorised projects',
    ar: 'كل المشاريع المصرح بها',
    ur: 'تمام مجاز پراجیکٹس',
    hi: 'सभी अधिकृत प्रोजेक्ट',
  );
  static const period = TranslatableString(
    en: 'Period',
    ar: 'الفترة',
    ur: 'مدت',
    hi: 'अवधि',
  );
  static const section = TranslatableString(
    en: 'Section',
    ar: 'القسم',
    ur: 'سیکشن',
    hi: 'अनुभाग',
  );
  static const project = TranslatableString(
    en: 'Project',
    ar: 'المشروع',
    ur: 'پراجیکٹ',
    hi: 'प्रोजेक्ट',
  );
  static const months = TranslatableString(
    en: 'months',
    ar: 'أشهر',
    ur: 'ماہ',
    hi: 'महीने',
  );
  static const refresh = TranslatableString(
    en: 'Refresh',
    ar: 'تحديث',
    ur: 'تازہ کریں',
    hi: 'रीफ्रेश',
  );
  static const lastConfirmed = TranslatableString(
    en: 'Last server confirmation',
    ar: 'آخر تأكيد من الخادم',
    ur: 'آخری سرور تصدیق',
    hi: 'अंतिम सर्वर पुष्टि',
  );
  static const partialTitle = TranslatableString(
    en: 'Some modules are not included',
    ar: 'بعض الوحدات غير مشمولة',
    ur: 'کچھ ماڈیول شامل نہیں ہیں',
    hi: 'कुछ मॉड्यूल शामिल नहीं हैं',
  );
  static const partialDescription = TranslatableString(
    en: 'Analytics never fills unavailable information with zero. Open the coverage panel to see what this account may view.',
    ar: 'لا تستبدل التحليلات المعلومات غير المتاحة بصفر. افتح لوحة التغطية لمعرفة ما يمكن لهذا الحساب رؤيته.',
    ur: 'تجزیات غیر دستیاب معلومات کو صفر نہیں دکھاتے۔ اس اکاؤنٹ کی رسائی دیکھنے کے لیے کوریج پینل کھولیں۔',
    hi: 'एनालिटिक्स अनुपलब्ध जानकारी को शून्य नहीं दिखाता। इस खाते की दृश्यता के लिए कवरेज पैनल खोलें।',
  );
  static const projectsTitle = TranslatableString(
    en: 'Projects',
    ar: 'المشاريع',
    ur: 'پراجیکٹس',
    hi: 'प्रोजेक्ट',
  );
  static const materialFlowTitle = TranslatableString(
    en: 'Material Requests',
    ar: 'طلبات المواد',
    ur: 'میٹریل ریکویسٹ',
    hi: 'मटेरियल रिक्वेस्ट',
  );
  static const monthlyMovement = TranslatableString(
    en: 'Monthly movement',
    ar: 'الحركة الشهرية',
    ur: 'ماہانہ حرکت',
    hi: 'मासिक गतिविधि',
  );
  static const submitted = TranslatableString(
    en: 'Submitted',
    ar: 'مقدم',
    ur: 'جمع شدہ',
    hi: 'जमा',
  );
  static const closed = TranslatableString(
    en: 'Closed',
    ar: 'مغلق',
    ur: 'بند',
    hi: 'बंद',
  );
  static const active = TranslatableString(
    en: 'Active',
    ar: 'نشط',
    ur: 'فعال',
    hi: 'सक्रिय',
  );
  static const onHold = TranslatableString(
    en: 'On hold',
    ar: 'معلق',
    ur: 'روکا ہوا',
    hi: 'होल्ड पर',
  );
  static const completed = TranslatableString(
    en: 'Completed',
    ar: 'مكتمل',
    ur: 'مکمل',
    hi: 'पूर्ण',
  );
  static const draft = TranslatableString(
    en: 'Draft',
    ar: 'مسودة',
    ur: 'ڈرافٹ',
    hi: 'ड्राफ्ट',
  );
  static const archived = TranslatableString(
    en: 'Archived',
    ar: 'مؤرشف',
    ur: 'محفوظ شدہ',
    hi: 'संग्रहीत',
  );
  static const totalRequests = TranslatableString(
    en: 'All requests',
    ar: 'كل الطلبات',
    ur: 'تمام درخواستیں',
    hi: 'सभी अनुरोध',
  );
  static const openRequests = TranslatableString(
    en: 'Open',
    ar: 'مفتوح',
    ur: 'کھلی',
    hi: 'खुले',
  );
  static const needsAction = TranslatableString(
    en: 'Needs your action',
    ar: 'يتطلب إجراءك',
    ur: 'آپ کی کارروائی درکار',
    hi: 'आपकी कार्रवाई चाहिए',
  );
  static const deliveryExceptions = TranslatableString(
    en: 'Delivery exceptions',
    ar: 'استثناءات التسليم',
    ur: 'ڈیلیوری کے مسائل',
    hi: 'डिलीवरी अपवाद',
  );
  static const coverageTitle = TranslatableString(
    en: 'Data coverage',
    ar: 'تغطية البيانات',
    ur: 'ڈیٹا کوریج',
    hi: 'डेटा कवरेज',
  );
  static const coverageDescription = TranslatableString(
    en: 'This explains which source modules are included for the signed-in account.',
    ar: 'يوضح هذا وحدات المصدر المشمولة للحساب المسجل.',
    ur: 'یہ بتاتا ہے کہ سائن اِن اکاؤنٹ کے لیے کون سے اصل ماڈیول شامل ہیں۔',
    hi: 'यह बताता है कि साइन-इन खाते के लिए कौन-से स्रोत मॉड्यूल शामिल हैं।',
  );
  static const available = TranslatableString(
    en: 'Included',
    ar: 'مشمول',
    ur: 'شامل',
    hi: 'शामिल',
  );
  static const sourceOnly = TranslatableString(
    en: 'Open source module',
    ar: 'افتح وحدة المصدر',
    ur: 'اصل ماڈیول کھولیں',
    hi: 'स्रोत मॉड्यूल खोलें',
  );
  static const denied = TranslatableString(
    en: 'Not available to this account',
    ar: 'غير متاح لهذا الحساب',
    ur: 'اس اکاؤنٹ کے لیے دستیاب نہیں',
    hi: 'इस खाते के लिए उपलब्ध नहीं',
  );
  static const openProjects = TranslatableString(
    en: 'Open Projects',
    ar: 'فتح المشاريع',
    ur: 'پراجیکٹس کھولیں',
    hi: 'प्रोजेक्ट खोलें',
  );
  static const openRequestsButton = TranslatableString(
    en: 'Open Material Requests',
    ar: 'فتح طلبات المواد',
    ur: 'میٹریل ریکویسٹ کھولیں',
    hi: 'मटेरियल रिक्वेस्ट खोलें',
  );
  static const tryAgain = TranslatableString(
    en: 'Try again',
    ar: 'حاول مرة أخرى',
    ur: 'دوبارہ کوشش کریں',
    hi: 'फिर प्रयास करें',
  );
  static const unableTitle = TranslatableString(
    en: 'Analytics could not be loaded',
    ar: 'تعذر تحميل التحليلات',
    ur: 'تجزیات لوڈ نہیں ہو سکے',
    hi: 'एनालिटिक्स लोड नहीं हो सका',
  );
  static const noData = TranslatableString(
    en: 'No authorised records in this view',
    ar: 'لا توجد سجلات مصرح بها في هذا العرض',
    ur: 'اس منظر میں کوئی مجاز ریکارڈ نہیں',
    hi: 'इस दृश्य में कोई अधिकृत रिकॉर्ड नहीं',
  );
  static const projectSource = TranslatableString(
    en: 'Projects',
    ar: 'المشاريع',
    ur: 'پراجیکٹس',
    hi: 'प्रोजेक्ट',
  );
  static const requestsSource = TranslatableString(
    en: 'Material Requests',
    ar: 'طلبات المواد',
    ur: 'میٹریل ریکویسٹ',
    hi: 'मटेरियल रिक्वेस्ट',
  );
  static const accountsSource = TranslatableString(
    en: 'Accounts',
    ar: 'الحسابات',
    ur: 'اکاؤنٹس',
    hi: 'अकाउंट्स',
  );
  static const workforceSource = TranslatableString(
    en: 'Workforce',
    ar: 'القوى العاملة',
    ur: 'افرادی قوت',
    hi: 'कार्यबल',
  );
  static const rentalsSource = TranslatableString(
    en: 'Rentals',
    ar: 'الإيجارات',
    ur: 'رینٹلز',
    hi: 'रेंटल',
  );
  static const inventorySource = TranslatableString(
    en: 'Inventory',
    ar: 'المخزون',
    ur: 'انوینٹری',
    hi: 'इन्वेंटरी',
  );
  static const auditSource = TranslatableString(
    en: 'Audit Trail',
    ar: 'سجل التدقيق',
    ur: 'آڈٹ ٹریل',
    hi: 'ऑडिट ट्रेल',
  );
  static const company = TranslatableString(
    en: 'Company',
    ar: 'الشركة',
    ur: 'کمپنی',
    hi: 'कंपनी',
  );
  static const readOnly = TranslatableString(
    en: 'Read only',
    ar: 'للقراءة فقط',
    ur: 'صرف پڑھنے کے لیے',
    hi: 'केवल पढ़ने के लिए',
  );
  static const importantForYou = TranslatableString(
    en: 'Important for you',
    ar: 'مهم بالنسبة لك',
    ur: 'آپ کے لیے اہم',
    hi: 'आपके लिए महत्वपूर्ण',
  );
  static const noImportantActions = TranslatableString(
    en: 'No confirmed actions need your attention right now.',
    ar: 'لا توجد إجراءات مؤكدة تتطلب انتباهك الآن.',
    ur: 'اس وقت کسی تصدیق شدہ کارروائی کو آپ کی توجہ درکار نہیں۔',
    hi: 'अभी किसी पुष्ट कार्रवाई को आपके ध्यान की आवश्यकता नहीं है।',
  );
  static const openSource = TranslatableString(
    en: 'View records',
    ar: 'فتح المصدر',
    ur: 'اصل ریکارڈ کھولیں',
    hi: 'स्रोत खोलें',
  );
  static const accountsAttention = TranslatableString(
    en: 'Accounts attention',
    ar: 'تنبيهات الحسابات',
    ur: 'اکاؤنٹس کی توجہ',
    hi: 'अकाउंट्स ध्यान',
  );
  static const workforceAttention = TranslatableString(
    en: 'Workforce attention',
    ar: 'تنبيهات القوى العاملة',
    ur: 'ورک فورس کی توجہ',
    hi: 'वर्कफोर्स ध्यान',
  );
  static const rentalsAttention = TranslatableString(
    en: 'Rental attention',
    ar: 'تنبيهات الإيجارات',
    ur: 'رینٹل کی توجہ',
    hi: 'रेंटल ध्यान',
  );
  static const financialStatus = TranslatableString(
    en: 'Financial Status',
    ar: 'الحالة المالية',
    ur: 'مالی حیثیت',
    hi: 'वित्तीय स्थिति',
  );
  static const currencyBoundary = TranslatableString(
    en: 'Amounts are shown per currency and are never combined.',
    ar: 'تُعرض المبالغ حسب العملة ولا يتم جمعها معًا.',
    ur: 'رقوم ہر کرنسی کے لحاظ سے دکھائے جاتے ہیں اور کبھی جمع نہیں کیے جاتے۔',
    hi: 'राशियां हर मुद्रा के अनुसार दिखाई जाती हैं और कभी जोड़ी नहीं जातीं।',
  );
  static const currencyGroups = TranslatableString(
    en: 'Currency groups',
    ar: 'مجموعات العملات',
    ur: 'کرنسی گروپس',
    hi: 'मुद्रा समूह',
  );
  static const overviewPartialDescription = TranslatableString(
    en: 'Only server-confirmed modules are shown here. Open Analytics to review access coverage.',
    ar: 'تظهر هنا الوحدات المؤكدة من الخادم فقط. افتح التحليلات لمراجعة نطاق الوصول.',
    ur: 'یہاں صرف سرور سے تصدیق شدہ ماڈیول دکھائے جاتے ہیں۔ رسائی کی تفصیل کے لیے تجزیات کھولیں۔',
    hi: 'यहां केवल सर्वर-पुष्ट मॉड्यूल दिखते हैं। पहुंच कवरेज देखने के लिए एनालिटिक्स खोलें।',
  );
  static const contractValue = TranslatableString(
    en: 'Contract value',
    ar: 'قيمة العقد',
    ur: 'معاہدے کی مالیت',
    hi: 'अनुबंध मूल्य',
  );
  static const claimed = TranslatableString(
    en: 'Claimed',
    ar: 'مطالب به',
    ur: 'کلیم شدہ',
    hi: 'दावा किया',
  );
  static const certified = TranslatableString(
    en: 'Certified',
    ar: 'معتمد',
    ur: 'تصدیق شدہ',
    hi: 'प्रमाणित',
  );
  static const receivedMoney = TranslatableString(
    en: 'Received',
    ar: 'مستلم',
    ur: 'وصول شدہ',
    hi: 'प्राप्त',
  );
  static const outstanding = TranslatableString(
    en: 'Outstanding',
    ar: 'مستحق',
    ur: 'بقایا',
    hi: 'बकाया',
  );
  static const projectReview = TranslatableString(
    en: 'Project review',
    ar: 'مراجعة المشاريع',
    ur: 'پراجیکٹ جائزہ',
    hi: 'प्रोजेक्ट समीक्षा',
  );
  static const projectReviewDescription = TranslatableString(
    en: 'Open work and current ownership across the authorised portfolio.',
    ar: 'العمل المفتوح والملكية الحالية عبر المحفظة المصرح بها.',
    ur: 'مجاز پورٹ فولیو میں کھلا کام اور موجودہ ذمہ داری۔',
    hi: 'अधिकृत पोर्टफोलियो में खुला काम और वर्तमान जिम्मेदारी।',
  );
  static const status = TranslatableString(
    en: 'Status',
    ar: 'الحالة',
    ur: 'حالت',
    hi: 'स्थिति',
  );
  static const owner = TranslatableString(
    en: 'Owner',
    ar: 'المسؤول',
    ur: 'ذمہ دار',
    hi: 'जिम्मेदार',
  );
  static const actions = TranslatableString(
    en: 'Actions',
    ar: 'الإجراءات',
    ur: 'کارروائیاں',
    hi: 'कार्रवाइयां',
  );
  static const latest = TranslatableString(
    en: 'Latest',
    ar: 'الأحدث',
    ur: 'تازہ ترین',
    hi: 'नवीनतम',
  );
  static const materialPipeline = TranslatableString(
    en: 'Material request pipeline',
    ar: 'مسار طلبات المواد',
    ur: 'میٹریل ریکویسٹ پائپ لائن',
    hi: 'मटेरियल रिक्वेस्ट पाइपलाइन',
  );
  static const awaitingApproval = TranslatableString(
    en: 'Awaiting approval',
    ar: 'بانتظار الموافقة',
    ur: 'منظوری کا انتظار',
    hi: 'अनुमोदन की प्रतीक्षा',
  );
  static const toArrange = TranslatableString(
    en: 'To arrange',
    ar: 'للتجهيز',
    ur: 'ارینج کرنا ہے',
    hi: 'व्यवस्था करनी है',
  );
  static const dispatchReady = TranslatableString(
    en: 'Dispatch ready',
    ar: 'جاهز للإرسال',
    ur: 'ڈسپیچ کے لیے تیار',
    hi: 'डिस्पैच के लिए तैयार',
  );
  static const receiptPending = TranslatableString(
    en: 'Receipt pending',
    ar: 'بانتظار الاستلام',
    ur: 'وصولی زیر التوا',
    hi: 'प्राप्ति लंबित',
  );
  static const approvedWorkforceEvidence = TranslatableString(
    en: 'Approved workforce evidence',
    ar: 'سجلات القوى العاملة المعتمدة',
    ur: 'منظور شدہ ورک فورس ریکارڈ',
    hi: 'स्वीकृत वर्कफोर्स रिकॉर्ड',
  );
  static const regularHours = TranslatableString(
    en: 'Regular hours',
    ar: 'الساعات العادية',
    ur: 'باقاعدہ گھنٹے',
    hi: 'नियमित घंटे',
  );
  static const overtimeHours = TranslatableString(
    en: 'Overtime hours',
    ar: 'ساعات العمل الإضافي',
    ur: 'اوور ٹائم گھنٹے',
    hi: 'ओवरटाइम घंटे',
  );
  static const hoursShort = TranslatableString(
    en: 'h',
    ar: 'س',
    ur: 'گھنٹے',
    hi: 'घं',
  );
  static const minutesShort = TranslatableString(
    en: 'm',
    ar: 'د',
    ur: 'منٹ',
    hi: 'मि',
  );
  static const activeWorkers = TranslatableString(
    en: 'Active workers',
    ar: 'العمال النشطون',
    ur: 'فعال کارکن',
    hi: 'सक्रिय कर्मचारी',
  );
  static const attendanceNotEntered = TranslatableString(
    en: 'Attendance not entered today',
    ar: 'لم يُدخل الحضور اليوم',
    ur: 'آج حاضری درج نہیں ہوئی',
    hi: 'आज उपस्थिति दर्ज नहीं हुई',
  );
  static const periodsPending = TranslatableString(
    en: 'Monthly periods pending',
    ar: 'الفترات الشهرية المعلقة',
    ur: 'ماہانہ مدت زیر التوا',
    hi: 'मासिक अवधि लंबित',
  );
  static const approvedEvidenceNote = TranslatableString(
    en: 'Hours use the latest approved monthly snapshots only. They are not a productivity score.',
    ar: 'تستخدم الساعات أحدث اللقطات الشهرية المعتمدة فقط، وليست تقييمًا للإنتاجية.',
    ur: 'گھنٹے صرف تازہ ترین منظور شدہ ماہانہ ریکارڈ سے ہیں؛ یہ کارکردگی کا اسکور نہیں۔',
    hi: 'घंटे केवल नवीनतम स्वीकृत मासिक रिकॉर्ड से हैं; यह उत्पादकता स्कोर नहीं है।',
  );
  static const rentalBusiness = TranslatableString(
    en: 'Rental',
    ar: 'الإيجارات',
    ur: 'رینٹل',
    hi: 'रेंटल',
  );
  static const propertiesOccupied = TranslatableString(
    en: 'Properties occupied',
    ar: 'العقارات المشغولة',
    ur: 'زیر استعمال جائیدادیں',
    hi: 'कब्जे वाली संपत्तियां',
  );
  static const monthlyRentRoll = TranslatableString(
    en: 'Monthly rent roll',
    ar: 'الإيجار الشهري',
    ur: 'ماہانہ کرایہ',
    hi: 'मासिक किराया',
  );
  static const collectedThisMonth = TranslatableString(
    en: 'Collected this month',
    ar: 'المحصل هذا الشهر',
    ur: 'اس ماہ وصول شدہ',
    hi: 'इस माह प्राप्त',
  );
  static const leaseChequeAttention = TranslatableString(
    en: 'Lease / cheque attention',
    ar: 'تنبيه العقود والشيكات',
    ur: 'لیز / چیک کی توجہ',
    hi: 'लीज / चेक ध्यान',
  );
  static const confirmedSource = TranslatableString(
    en: 'Server-confirmed source',
    ar: 'مصدر مؤكد من الخادم',
    ur: 'سرور سے تصدیق شدہ ذریعہ',
    hi: 'सर्वर-पुष्ट स्रोत',
  );
  static const actionRequired = TranslatableString(
    en: 'Action required',
    ar: 'إجراء مطلوب',
    ur: 'کارروائی درکار',
    hi: 'कार्रवाई आवश्यक',
  );
  static const overdueInvoice = TranslatableString(
    en: 'Overdue invoice',
    ar: 'فاتورة متأخرة',
    ur: 'تاخیر شدہ انوائس',
    hi: 'अतिदेय चालान',
  );
  static const reviewTimesheets = TranslatableString(
    en: 'Monthly timesheets need review',
    ar: 'تحتاج كشوف الدوام الشهرية إلى مراجعة',
    ur: 'ماہانہ ٹائم شیٹس کا جائزہ درکار ہے',
    hi: 'मासिक टाइमशीट की समीक्षा आवश्यक है',
  );
  static const completeAttendance = TranslatableString(
    en: "Complete today's attendance",
    ar: 'أكمل حضور اليوم',
    ur: 'آج کی حاضری مکمل کریں',
    hi: 'आज की उपस्थिति पूरी करें',
  );
  static const correctReturnedTimesheets = TranslatableString(
    en: 'Returned timesheets need correction',
    ar: 'تحتاج كشوف الدوام المعادة إلى تصحيح',
    ur: 'واپس کی گئی ٹائم شیٹس درست کریں',
    hi: 'लौटाई गई टाइमशीट में सुधार करें',
  );
  static const finalizeTimesheets = TranslatableString(
    en: 'Timesheets are ready for final review',
    ar: 'كشوف الدوام جاهزة للمراجعة النهائية',
    ur: 'ٹائم شیٹس حتمی جائزے کے لیے تیار ہیں',
    hi: 'टाइमशीट अंतिम समीक्षा के लिए तैयार हैं',
  );
  static const reviewReopenRequests = TranslatableString(
    en: 'Timesheet reopen requests need a decision',
    ar: 'تحتاج طلبات إعادة فتح كشف الدوام إلى قرار',
    ur: 'ٹائم شیٹ دوبارہ کھولنے کی درخواست پر فیصلہ کریں',
    hi: 'टाइमशीट दोबारा खोलने के अनुरोध पर निर्णय लें',
  );
  static const resolveWorkforceSetup = TranslatableString(
    en: 'Workforce setup needs attention',
    ar: 'يحتاج إعداد القوى العاملة إلى اهتمام',
    ur: 'ورک فورس سیٹ اپ پر توجہ درکار ہے',
    hi: 'वर्कफोर्स सेटअप पर ध्यान आवश्यक है',
  );
  static const workersWithoutAttendance = TranslatableString(
    en: 'workers still need a confirmed status for today',
    ar: 'عمال ما زالوا بحاجة إلى حالة مؤكدة لليوم',
    ur: 'کارکنوں کی آج کی تصدیق شدہ حاضری باقی ہے',
    hi: 'कर्मचारियों की आज की पुष्टि की गई स्थिति बाकी है',
  );
  static const periodsAwaitingReview = TranslatableString(
    en: 'monthly periods are waiting in Timesheets',
    ar: 'فترات شهرية تنتظر في كشوف الدوام',
    ur: 'ماہانہ مدت ٹائم شیٹس میں منتظر ہیں',
    hi: 'मासिक अवधि टाइमशीट में प्रतीक्षारत हैं',
  );
  static const returnedForCorrection = TranslatableString(
    en: 'timesheets were returned with a recorded reason',
    ar: 'أعيدت كشوف الدوام مع سبب مسجل',
    ur: 'ٹائم شیٹس درج شدہ وجہ کے ساتھ واپس کی گئی ہیں',
    hi: 'टाइमशीट दर्ज कारण के साथ लौटाई गई हैं',
  );
  static const readyForFinalReview = TranslatableString(
    en: 'timesheets are awaiting the final authorized step',
    ar: 'كشوف الدوام بانتظار الخطوة النهائية المصرح بها',
    ur: 'ٹائم شیٹس آخری مجاز مرحلے کی منتظر ہیں',
    hi: 'टाइमशीट अंतिम अधिकृत चरण की प्रतीक्षा में हैं',
  );
  static const reopenRequestsAwaitingDecision = TranslatableString(
    en: 'reopen requests are awaiting an authorized decision',
    ar: 'طلبات إعادة الفتح تنتظر قرارًا مصرحًا به',
    ur: 'دوبارہ کھولنے کی درخواستیں مجاز فیصلے کی منتظر ہیں',
    hi: 'दोबारा खोलने के अनुरोध अधिकृत निर्णय की प्रतीक्षा में हैं',
  );
  static const setupIssuesRequireAdmin = TranslatableString(
    en: 'configuration issues require Workforce administration',
    ar: 'تتطلب مشكلات الإعداد إدارة القوى العاملة',
    ur: 'سیٹ اپ کے مسائل کے لیے ورک فورس ایڈمنسٹریشن درکار ہے',
    hi: 'सेटअप समस्याओं के लिए वर्कफोर्स प्रशासन आवश्यक है',
  );
  static const openRequest = TranslatableString(
    en: 'Open request',
    ar: 'فتح الطلب',
    ur: 'درخواست کھولیں',
    hi: 'अनुरोध खोलें',
  );
  static const openAccounts = TranslatableString(
    en: 'Open Accounts',
    ar: 'فتح الحسابات',
    ur: 'اکاؤنٹس کھولیں',
    hi: 'अकाउंट्स खोलें',
  );
  static const openAttendance = TranslatableString(
    en: 'Open attendance',
    ar: 'فتح الحضور',
    ur: 'حاضری کھولیں',
    hi: 'उपस्थिति खोलें',
  );
  static const openTimesheets = TranslatableString(
    en: 'Open Timesheets',
    ar: 'فتح كشوف الدوام',
    ur: 'ٹائم شیٹس کھولیں',
    hi: 'टाइमशीट खोलें',
  );
  static const openWorkforceAdministration = TranslatableString(
    en: 'Open Workforce administration',
    ar: 'فتح إدارة القوى العاملة',
    ur: 'ورک فورس ایڈمنسٹریشن کھولیں',
    hi: 'वर्कफोर्स प्रशासन खोलें',
  );
  static const openWorkforce = TranslatableString(
    en: 'Open Workforce',
    ar: 'فتح القوى العاملة',
    ur: 'ورک فورس کھولیں',
    hi: 'कार्यबल खोलें',
  );
  static const openRental = TranslatableString(
    en: 'Open Rental',
    ar: 'فتح الإيجارات',
    ur: 'رینٹل کھولیں',
    hi: 'रेंटल खोलें',
  );
  static const receivedAgainstContract = TranslatableString(
    en: 'Received against contract value',
    ar: 'المستلم مقابل قيمة العقد',
    ur: 'معاہدے کی مالیت کے مقابل وصول شدہ',
    hi: 'अनुबंध मूल्य के मुकाबले प्राप्त',
  );
  static const rentalFollowUp = TranslatableString(
    en: 'Review leases and cheques',
    ar: 'مراجعة العقود والشيكات',
    ur: 'لیز اور چیکس کا جائزہ لیں',
    hi: 'लीज और चेक की समीक्षा करें',
  );
  static const requestsNeedAction = TranslatableString(
    en: 'Material requests need action',
    ar: 'طلبات مواد تتطلب إجراءً',
    ur: 'میٹریل ریکویسٹ پر کارروائی درکار',
    hi: 'मटेरियल अनुरोधों पर कार्रवाई चाहिए',
  );

  static TranslatableString errorFor(
    YorksV1DomainErrorCode code,
  ) => switch (code) {
    YorksV1DomainErrorCode.offline => const TranslatableString(
      en: 'Connect to the internet, then try again. Analytics is never calculated from an offline cache.',
      ar: 'اتصل بالإنترنت ثم حاول مرة أخرى. لا يتم حساب التحليلات من ذاكرة مؤقتة غير متصلة.',
      ur: 'انٹرنیٹ سے جڑیں، پھر دوبارہ کوشش کریں۔ تجزیات آف لائن کیش سے نہیں بنائے جاتے۔',
      hi: 'इंटरनेट से जुड़ें, फिर प्रयास करें। एनालिटिक्स ऑफलाइन कैश से नहीं बनाया जाता।',
    ),
    YorksV1DomainErrorCode.unauthorized => const TranslatableString(
      en: 'This account no longer has permission to view Analytics.',
      ar: 'لم يعد لهذا الحساب إذن لعرض التحليلات.',
      ur: 'اس اکاؤنٹ کو اب تجزیات دیکھنے کی اجازت نہیں ہے۔',
      hi: 'इस खाते को अब एनालिटिक्स देखने की अनुमति नहीं है।',
    ),
    _ => const TranslatableString(
      en: 'The protected server could not confirm this view. No values have been assumed.',
      ar: 'تعذر على الخادم المحمي تأكيد هذا العرض. لم يتم افتراض أي قيم.',
      ur: 'محفوظ سرور اس منظر کی تصدیق نہیں کر سکا۔ کوئی قدر فرض نہیں کی گئی۔',
      hi: 'सुरक्षित सर्वर इस दृश्य की पुष्टि नहीं कर सका। कोई मान अनुमानित नहीं है।',
    ),
  };
}
