import 'app_strings.dart';

/// Shared, localized Yorks V1 copy for the R35 auth and workspace chrome.
///
/// Keeping the shell vocabulary here prevents the navigation and sign-in
/// surfaces from becoming a second, prototype-only set of English strings.
abstract final class YorksV1ShellStrings {
  static const analytics = TranslatableString(
    en: 'Analytics',
    ar: 'التحليلات',
    ur: 'تجزیات',
    hi: 'विश्लेषण',
  );
  static const workforce = TranslatableString(
    en: 'Workforce',
    ar: 'القوى العاملة',
    ur: 'افرادی قوت',
    hi: 'कार्यबल',
  );
  static const workforceTimesheets = TranslatableString(
    en: 'Timesheets',
    ar: 'سجلات الدوام',
    ur: 'ٹائم شیٹس',
    hi: 'टाइमशीट',
  );
  static const workforceAdministration = TranslatableString(
    en: 'Workforce administration',
    ar: 'إدارة القوى العاملة',
    ur: 'افرادی قوت کا انتظام',
    hi: 'कार्यबल प्रशासन',
  );
  static const accounts = TranslatableString(
    en: 'Accounts',
    ar: 'الحسابات',
    ur: 'اکاؤنٹس',
    hi: 'अकाउंट्स',
  );
  static const accountantWorkspace = TranslatableString(
    en: 'Accountant workspace',
    ar: 'مساحة عمل المحاسب',
    ur: 'اکاؤنٹنٹ ورک اسپیس',
    hi: 'अकाउंटेंट कार्यस्थान',
  );
  static const prWorkspace = TranslatableString(
    en: 'PR workspace',
    ar: 'مساحة عمل العلاقات العامة',
    ur: 'پی آر ورک اسپیس',
    hi: 'पीआर कार्यस्थान',
  );
  static const prHero = TranslatableString(
    en: 'People and workforce',
    ar: 'الموظفون والقوى العاملة',
    ur: 'عملہ اور افرادی قوت',
    hi: 'कर्मचारी और कार्यबल',
  );
  static const prHeroDescription = TranslatableString(
    en: 'User accounts, workers, attendance and rental properties. Projects and Accounts are view only.',
    ar: 'حسابات المستخدمين والعمال والحضور والعقارات المؤجرة. المشاريع والحسابات للعرض فقط.',
    ur: 'یوزر اکاؤنٹس، ورکرز، حاضری اور کرائے کی پراپرٹیز۔ پراجیکٹس اور اکاؤنٹس صرف دیکھنے کے لیے ہیں۔',
    hi: 'यूज़र अकाउंट, कर्मचारी, उपस्थिति और किराये की संपत्तियाँ। प्रोजेक्ट और अकाउंट्स केवल देखने के लिए हैं।',
  );
  static const projectAccounts = TranslatableString(
    en: 'Project Accounts',
    ar: 'حسابات المشاريع',
    ur: 'پراجیکٹ اکاؤنٹس',
    hi: 'प्रोजेक्ट अकाउंट्स',
  );
  static const billingProgress = TranslatableString(
    en: 'Billing Progress',
    ar: 'تقدم الفوترة',
    ur: 'بلنگ پیشرفت',
    hi: 'बिलिंग प्रगति',
  );
  static const accountsClaims = TranslatableString(
    en: 'Claims & Invoices',
    ar: 'المطالبات والفواتير',
    ur: 'کلیمز اور انوائسز',
    hi: 'क्लेम और इनवॉइस',
  );
  static const receiptsPdc = TranslatableString(
    en: 'Receipts & PDC',
    ar: 'المقبوضات والشيكات الآجلة',
    ur: 'رسیدیں اور PDC',
    hi: 'रसीदें और PDC',
  );
  static const supplierBills = TranslatableString(
    en: 'Supplier Bills',
    ar: 'فواتير الموردين',
    ur: 'سپلائر بلز',
    hi: 'सप्लायर बिल',
  );
  static const dueSchedule = TranslatableString(
    en: 'Due Schedule',
    ar: 'جدول الاستحقاقات',
    ur: 'ڈیو شیڈول',
    hi: 'देय समय-सारणी',
  );
  static const accountsDocuments = TranslatableString(
    en: 'Documents',
    ar: 'المستندات',
    ur: 'دستاویزات',
    hi: 'दस्तावेज़',
  );
  static const accountsReports = TranslatableString(
    en: 'Reports',
    ar: 'التقارير',
    ur: 'رپورٹس',
    hi: 'रिपोर्ट',
  );

  /// The Accounts activity tab. Named apart from the company Audit Trail so
  /// Admin never sees two pages with the same name.
  static const accountsAuditTrail = TranslatableString(
    en: 'Activity',
    ar: 'النشاط',
    ur: 'سرگرمی',
    hi: 'गतिविधि',
  );
  static const accountsOverviewTab = TranslatableString(
    en: 'Overview',
    ar: 'نظرة عامة',
    ur: 'جائزہ',
    hi: 'अवलोकन',
  );
  static const accountsProjectsTab = TranslatableString(
    en: 'Projects',
    ar: 'المشاريع',
    ur: 'پراجیکٹس',
    hi: 'प्रोजेक्ट',
  );
  static const accountsSections = TranslatableString(
    en: 'Accounts sections',
    ar: 'أقسام الحسابات',
    ur: 'اکاؤنٹس کے حصے',
    hi: 'अकाउंट्स अनुभाग',
  );

  /// Sidebar section for the material flow: requests, dispatches, returns
  /// and inventory, kept together for every role.
  static const materialsSection = TranslatableString(
    en: 'Materials',
    ar: 'المواد',
    ur: 'میٹریلز',
    hi: 'सामग्री',
  );
  static const collaboration = TranslatableString(
    en: 'Collaboration',
    ar: 'التعاون',
    ur: 'تعاون',
    hi: 'सहयोग',
  );
  static const companyName = TranslatableString(
    en: 'Yorks AC. & Ref.',
    ar: 'يوركس للتكييف والتبريد',
    ur: 'یارکس اے سی اینڈ ریف',
    hi: 'यॉर्क्स एसी एंड रेफ.',
  );
  static const companyLegalName = TranslatableString(
    en: 'Yorks Air Conditioning & Refrigeration LLC-SPC',
    ar: 'يوركس للتكييف والتبريد ذ.م.م - ش.ش.و',
    ur: 'یارکس ایئر کنڈیشننگ اینڈ ریفریجریشن ایل ایل سی-ایس پی سی',
    hi: 'यॉर्क्स एयर कंडीशनिंग एंड रेफ्रिजरेशन एलएलसी-एसपीसी',
  );
  static const companyLegalNameCompact = TranslatableString(
    en: 'Air Conditioning &\nRefrigeration LLC-SPC',
    ar: 'تكييف الهواء والتبريد\nذ.م.م - ش.ش.و',
    ur: 'ایئر کنڈیشننگ اور\nریفریجریشن ایل ایل سی-ایس پی سی',
    hi: 'एयर कंडीशनिंग और\nरेफ्रिजरेशन एलएलसी-एसपीसी',
  );
  static const operationalWorkspace = TranslatableString(
    en: 'Operational workspace',
    ar: 'مساحة العمل التشغيلية',
    ur: 'آپریشنل ورک اسپیس',
    hi: 'ऑपरेशनल वर्कस्पेस',
  );
  static const preparingWorkspace = TranslatableString(
    en: 'Preparing your workspace…',
    ar: 'جارٍ تجهيز مساحة العمل…',
    ur: 'آپ کا ورک اسپیس تیار کیا جا رہا ہے…',
    hi: 'आपका कार्यक्षेत्र तैयार किया जा रहा है…',
  );
  static const openingYorks = TranslatableString(
    en: 'Opening Yorks…',
    ar: 'جارٍ فتح يوركس…',
    ur: 'یارکس کھولا جا رہا ہے…',
    hi: 'यॉर्क्स खोला जा रहा है…',
  );
  static const startupFailedTitle = TranslatableString(
    en: 'Yorks could not start',
    ar: 'تعذر تشغيل يوركس',
    ur: 'یارکس شروع نہیں ہو سکا',
    hi: 'यॉर्क्स शुरू नहीं हो सका',
  );
  static const startupFailedBody = TranslatableString(
    en: 'Check your connection and try again. Your work has not been changed.',
    ar: 'تحقق من الاتصال وحاول مرة أخرى. لم يتم تغيير عملك.',
    ur: 'اپنا کنکشن چیک کریں اور دوبارہ کوشش کریں۔ آپ کے کام میں کوئی تبدیلی نہیں ہوئی۔',
    hi: 'अपना कनेक्शन जांचें और फिर कोशिश करें। आपका काम बदला नहीं गया है।',
  );
  static const secureProjectWorkspace = TranslatableString(
    en: 'Secure project workspace',
    ar: 'مساحة عمل مشروع آمنة',
    ur: 'محفوظ پراجیکٹ ورک اسپیس',
    hi: 'सुरक्षित प्रोजेक्ट कार्यक्षेत्र',
  );
  static const projectManagementSystem = TranslatableString(
    en: 'Air Conditioning & Refrigeration\nProject Management System',
    ar: 'نظام إدارة مشاريع التكييف والتبريد',
    ur: 'ایئر کنڈیشننگ اور ریفریجریشن\nپراجیکٹ مینجمنٹ سسٹم',
    hi: 'एयर कंडीशनिंग और रेफ्रिजरेशन\nप्रोजेक्ट प्रबंधन प्रणाली',
  );
  static const oneSourceOfTruthForEveryProject = TranslatableString(
    en: 'One source of truth for every project.',
    ar: 'مصدر واحد للحقيقة لكل مشروع.',
    ur: 'ہر پراجیکٹ کے لیے سچائی کا ایک ذریعہ۔',
    hi: 'हर प्रोजेक्ट के लिए सत्य का एक स्रोत।',
  );
  static const byContinuingYouAgreeToOur = TranslatableString(
    en: 'By continuing, you agree to our',
    ar: 'بالمتابعة، فإنك توافق على',
    ur: 'جاری رکھنے سے، آپ ہماری شرائط سے اتفاق کرتے ہیں',
    hi: 'जारी रखकर, आप हमारी शर्तों से सहमत होते हैं',
  );
  static const and = TranslatableString(
    en: 'and',
    ar: 'و',
    ur: 'اور',
    hi: 'और',
  );
  static const signInHero = TranslatableString(
    en: 'Keep every project, material request and delivery easy to follow.',
    ar: 'اجعل كل مشروع وطلب مواد وتسليم سهل المتابعة.',
    ur: 'ہر پراجیکٹ، میٹیریل ریکویسٹ اور ڈلیوری کو آسانی سے ٹریک کریں۔',
    hi: 'हर प्रोजेक्ट, सामग्री अनुरोध और डिलीवरी को आसानी से ट्रैक करें।',
  );
  static const signInHeroDescription = TranslatableString(
    en: 'Projects, BOQ folders, Material Requests, procurement dispatches and documents remain connected in one dependable workspace.',
    ar: 'تبقى المشاريع ومجلدات جدول الكميات وطلبات المواد والإرساليات والمستندات متصلة في مساحة عمل موثوقة واحدة.',
    ur: 'پراجیکٹس، BOQ فولڈرز، میٹیریل ریکویسٹس، پروکیورمنٹ ڈسپیچز اور دستاویزات ایک قابلِ اعتماد ورک اسپیس میں منسلک رہتے ہیں۔',
    hi: 'प्रोजेक्ट, बीओक्यू फ़ोल्डर, सामग्री अनुरोध, खरीद डिस्पैच और दस्तावेज़ एक भरोसेमंद कार्यक्षेत्र में जुड़े रहते हैं।',
  );
  static const signInDescription = TranslatableString(
    en: 'Use your Yorks company email and password. User access is created and managed by Admin.',
    ar: 'استخدم بريد Yorks الإلكتروني وكلمة المرور. يتم إنشاء وإدارة وصول المستخدم بواسطة المسؤول.',
    ur: 'اپنی Yorks کمپنی ای میل اور پاس ورڈ استعمال کریں۔ صارف کی رسائی ایڈمن بناتا اور منظم کرتا ہے۔',
    hi: 'अपने Yorks कंपनी ईमेल और पासवर्ड का उपयोग करें। उपयोगकर्ता पहुंच एडमिन द्वारा बनाई और प्रबंधित की जाती है।',
  );
  static const protectedSessionStatus = TranslatableString(
    en: 'Protected session',
    ar: 'جلسة محمية',
    ur: 'محفوظ سیشن',
    hi: 'सुरक्षित सत्र',
  );
  static const authorisedPersonnelOnly = TranslatableString(
    en: 'Authorised Yorks AC. & Ref. personnel only',
    ar: 'لموظفي Yorks AC. & Ref. المصرح لهم فقط',
    ur: 'صرف مجاز Yorks AC. & Ref. عملہ',
    hi: 'केवल अधिकृत Yorks AC. & Ref. कर्मियों के लिए',
  );
  static const savedJustNow = TranslatableString(
    en: 'Saved just now',
    ar: 'تم الحفظ الآن',
    ur: 'ابھی محفوظ ہوا',
    hi: 'अभी सहेजा गया',
  );
  static const workspaceConnected = TranslatableString(
    en: 'Connected',
    ar: 'متصل',
    ur: 'منسلک',
    hi: 'कनेक्टेड',
  );
  static const workspaceSyncing = TranslatableString(
    en: 'Syncing changes',
    ar: 'جارٍ مزامنة التغييرات',
    ur: 'تبدیلیاں ہم آہنگ ہو رہی ہیں',
    hi: 'बदलाव सिंक हो रहे हैं',
  );
  static const workspaceOffline = TranslatableString(
    en: 'Offline',
    ar: 'غير متصل',
    ur: 'آف لائن',
    hi: 'ऑफ़लाइन',
  );
  static const workspaceReconnecting = TranslatableString(
    en: 'Reconnecting',
    ar: 'جارٍ إعادة الاتصال',
    ur: 'دوبارہ منسلک ہو رہا ہے',
    hi: 'फिर से कनेक्ट हो रहा है',
  );
  static const workspaceFailed = TranslatableString(
    en: 'Changes need attention',
    ar: 'التغييرات تحتاج إلى مراجعة',
    ur: 'تبدیلیاں توجہ چاہتی ہیں',
    hi: 'बदलावों पर ध्यान चाहिए',
  );
  static const workspaceLocalDraft = TranslatableString(
    en: 'Local draft',
    ar: 'مسودة محلية',
    ur: 'مقامی مسودہ',
    hi: 'स्थानीय ड्राफ़्ट',
  );
  static const workspaceConflict = TranslatableString(
    en: 'Conflict needs review',
    ar: 'التعارض يحتاج إلى مراجعة',
    ur: 'تنازع کا جائزہ درکار ہے',
    hi: 'संघर्ष की समीक्षा चाहिए',
  );
  static const goodAfternoon = TranslatableString(
    en: 'Good afternoon',
    ar: 'مساء الخير',
    ur: 'شب بخیر',
    hi: 'शुभ अपराह्न',
  );
  static const workspaceReady = TranslatableString(
    en: 'your workspace is ready.',
    ar: 'مساحة عملك جاهزة.',
    ur: 'آپ کا ورک اسپیس تیار ہے۔',
    hi: 'आपका कार्यक्षेत्र तैयार है।',
  );
  static const overviewWorkspaceDescription = TranslatableString(
    en: 'Create projects, organise BOQ folders and confirm delivered materials.',
    ar: 'أنشئ المشاريع ونظّم مجلدات جدول الكميات وأكد المواد المسلّمة.',
    ur: 'پراجیکٹس بنائیں، BOQ فولڈرز منظم کریں اور ڈیلیور شدہ مواد کی تصدیق کریں۔',
    hi: 'प्रोजेक्ट बनाएं, बीओक्यू फ़ोल्डर व्यवस्थित करें और वितरित सामग्री की पुष्टि करें।',
  );
  static const openRequests = TranslatableString(
    en: 'Open Requests',
    ar: 'الطلبات المفتوحة',
    ur: 'اوپن ریکویسٹس',
    hi: 'खुले अनुरोध',
  );
  static const needsYourAction = TranslatableString(
    en: 'Needs Your Action',
    ar: 'يتطلب إجراءك',
    ur: 'آپ کی کارروائی درکار ہے',
    hi: 'आपकी कार्रवाई आवश्यक है',
  );
  static const roleActionDescription = TranslatableString(
    en: 'Only the records that require this role are shown.',
    ar: 'تظهر فقط السجلات التي تتطلب هذا الدور.',
    ur: 'صرف وہ ریکارڈز دکھائے جاتے ہیں جن کے لیے یہ کردار درکار ہے۔',
    hi: 'केवल वे रिकॉर्ड दिखाए जाते हैं जिनके लिए इस भूमिका की आवश्यकता है।',
  );
  static const nothingWaiting = TranslatableString(
    en: 'Nothing is waiting for you',
    ar: 'لا يوجد ما ينتظرك',
    ur: 'آپ کے لیے کچھ زیرِ انتظار نہیں',
    hi: 'आपके लिए कुछ भी प्रतीक्षारत नहीं है',
  );
  static const nothingWaitingDescription = TranslatableString(
    en: 'Open Projects or Material Requests to continue working.',
    ar: 'افتح المشاريع أو طلبات المواد لمتابعة العمل.',
    ur: 'کام جاری رکھنے کے لیے پراجیکٹس یا میٹیریل ریکویسٹس کھولیں۔',
    hi: 'काम जारी रखने के लिए प्रोजेक्ट या सामग्री अनुरोध खोलें।',
  );
  static const workspaceScope = TranslatableString(
    en: 'BOQ · Requests · Documents',
    ar: 'جدول الكميات · الطلبات · المستندات',
    ur: 'BOQ · ریکویسٹس · دستاویزات',
    hi: 'बीओक्यू · अनुरोध · दस्तावेज़',
  );
  static const scope = TranslatableString(
    en: 'Scope',
    ar: 'النطاق',
    ur: 'اسکوپ',
    hi: 'दायरा',
  );
  static const viewAll = TranslatableString(
    en: 'View All',
    ar: 'عرض الكل',
    ur: 'سب دیکھیں',
    hi: 'सभी देखें',
  );
  static const connectedProjectControl = TranslatableString(
    en: 'Procurement Control & Inventory',
    ar: 'ضبط المشتريات والمخزون',
    ur: 'پروکیورمنٹ کنٹرول اور انوینٹری',
    hi: 'खरीद नियंत्रण और इन्वेंट्री',
  );
  static const engineerWorkspace = TranslatableString(
    en: 'Engineer Workspace',
    ar: 'مساحة عمل المهندس',
    ur: 'انجینئر ورک اسپیس',
    hi: 'इंजीनियर कार्यक्षेत्र',
  );
  static const procurementWorkspace = TranslatableString(
    en: 'Procurement Workspace',
    ar: 'مساحة عمل المشتريات',
    ur: 'پروکیورمنٹ ورک اسپیس',
    hi: 'खरीद कार्यक्षेत्र',
  );
  static const managementWorkspace = TranslatableString(
    en: 'Management Workspace',
    ar: 'مساحة عمل الإدارة',
    ur: 'مینجمنٹ ورک اسپیس',
    hi: 'प्रबंधन कार्यक्षेत्र',
  );
  static const workspaceSaved = TranslatableString(
    en: 'Workspace saved',
    ar: 'تم حفظ مساحة العمل',
    ur: 'ورک اسپیس محفوظ ہے',
    hi: 'कार्यस्थान सहेजा गया',
  );
  static const quickNavigation = TranslatableString(
    en: 'Quick navigation',
    ar: 'تنقل سريع',
    ur: 'فوری نیویگیشن',
    hi: 'त्वरित नेविगेशन',
  );
  static const collapsePanel = TranslatableString(
    en: 'Collapse panel',
    ar: 'طي اللوحة',
    ur: 'پینل سکیڑیں',
    hi: 'पैनल संक्षिप्त करें',
  );
  static const expandPanel = TranslatableString(
    en: 'Expand panel',
    ar: 'توسيع اللوحة',
    ur: 'پینل پھیلائیں',
    hi: 'पैनल विस्तृत करें',
  );
  static const searchWorkspace = TranslatableString(
    en: 'Search workspace',
    ar: 'البحث في مساحة العمل',
    ur: 'ورک اسپیس تلاش کریں',
    hi: 'कार्यस्थान खोजें',
  );
  static const searchOrJump = TranslatableString(
    en: 'Search or jump to…',
    ar: 'ابحث أو انتقل إلى…',
    ur: 'تلاش کریں یا یہاں جائیں…',
    hi: 'खोजें या यहां जाएं…',
  );
  static const searchHint = TranslatableString(
    en: 'Search projects, requests, BOQ, documents or materials…',
    ar: 'ابحث في المشاريع والطلبات وجدول الكميات والمستندات والمواد…',
    ur: 'پراجیکٹس، ریکویسٹس، BOQ، دستاویزات یا مواد تلاش کریں…',
    hi: 'प्रोजेक्ट, अनुरोध, बीओक्यू, दस्तावेज़ या सामग्री खोजें…',
  );
  static const searchResults = TranslatableString(
    en: 'Search results',
    ar: 'نتائج البحث',
    ur: 'تلاش کے نتائج',
    hi: 'खोज परिणाम',
  );
  static const searchModules = TranslatableString(
    en: 'Modules',
    ar: 'الوحدات',
    ur: 'ماڈیولز',
    hi: 'मॉड्यूल',
  );
  static const searchStartTyping = TranslatableString(
    en: 'Start typing to search the workspace',
    ar: 'ابدأ الكتابة للبحث في مساحة العمل',
    ur: 'ورک اسپیس تلاش کرنے کے لیے ٹائپ کریں',
    hi: 'कार्यस्थान खोजने के लिए लिखना शुरू करें',
  );
  static const searchNoResults = TranslatableString(
    en: 'No matching records found',
    ar: 'لم يتم العثور على سجلات مطابقة',
    ur: 'کوئی مماثل ریکارڈ نہیں ملا',
    hi: 'कोई मेल खाने वाला रिकॉर्ड नहीं मिला',
  );
  static const searchUnavailable = TranslatableString(
    en: 'Search is temporarily unavailable. Try again.',
    ar: 'البحث غير متاح مؤقتاً. حاول مرة أخرى.',
    ur: 'تلاش عارضی طور پر دستیاب نہیں۔ دوبارہ کوشش کریں۔',
    hi: 'खोज अभी उपलब्ध नहीं है। फिर प्रयास करें।',
  );
  static const searchPartial = TranslatableString(
    en: 'Some authorised records could not be checked. Available matches are shown.',
    ar: 'تعذر التحقق من بعض السجلات المصرح بها. تظهر النتائج المتاحة.',
    ur: 'کچھ مجاز ریکارڈز چیک نہیں ہو سکے۔ دستیاب نتائج دکھائے گئے ہیں۔',
    hi: 'कुछ अधिकृत रिकॉर्ड जांचे नहीं जा सके। उपलब्ध परिणाम दिखाए गए हैं।',
  );
  static const searchLoading = TranslatableString(
    en: 'Searching your authorised workspace…',
    ar: 'جارٍ البحث في مساحة العمل المصرح بها…',
    ur: 'آپ کے مجاز ورک اسپیس میں تلاش جاری ہے…',
    hi: 'आपके अधिकृत कार्यस्थान में खोज जारी है…',
  );
  static const searchKeyboardHint = TranslatableString(
    en: '↑ ↓ to move · Enter to open · Esc to close',
    ar: '↑ ↓ للتنقل · Enter للفتح · Esc للإغلاق',
    ur: '↑ ↓ منتقل کریں · Enter کھولیں · Esc بند کریں',
    hi: '↑ ↓ चलें · Enter खोलें · Esc बंद करें',
  );
  static const searchModule = TranslatableString(
    en: 'Module',
    ar: 'وحدة',
    ur: 'ماڈیول',
    hi: 'मॉड्यूल',
  );
  static const searchProject = TranslatableString(
    en: 'Project',
    ar: 'مشروع',
    ur: 'پراجیکٹ',
    hi: 'प्रोजेक्ट',
  );
  static const searchBoqGroup = TranslatableString(
    en: 'BOQ group',
    ar: 'مجموعة جدول الكميات',
    ur: 'BOQ گروپ',
    hi: 'बीओक्यू समूह',
  );
  static const searchBoqItem = TranslatableString(
    en: 'BOQ item',
    ar: 'بند جدول الكميات',
    ur: 'BOQ آئٹم',
    hi: 'बीओक्यू आइटम',
  );
  static const searchMaterialRequest = TranslatableString(
    en: 'Material request',
    ar: 'طلب مواد',
    ur: 'میٹیریل ریکویسٹ',
    hi: 'सामग्री अनुरोध',
  );
  static const searchMaterialItem = TranslatableString(
    en: 'Material item',
    ar: 'بند المواد',
    ur: 'میٹیریل آئٹم',
    hi: 'सामग्री आइटम',
  );
  static const searchDocument = TranslatableString(
    en: 'Document',
    ar: 'مستند',
    ur: 'دستاویز',
    hi: 'दस्तावेज़',
  );
  static const projectCloseoutControl = TranslatableString(
    en: 'Every project stays controlled from start to closeout.',
    ar: 'تحكم متكامل من المشروع حتى الإقفال.',
    ur: 'پراجیکٹ سے کلوز آؤٹ تک کنٹرول۔',
    hi: 'प्रोजेक्ट से क्लोज़आउट तक नियंत्रण।',
  );
  static const projectCloseoutDescription = TranslatableString(
    en: 'BOQ, materials, site requests and procurement remain connected in one dependable workspace.',
    ar: 'مساحة عمل مضبوطة للمشاريع وطلبات المواد وإثباتات التسليم والتتبع.',
    ur: 'پراجیکٹس، میٹیریل ریکویسٹ، ڈلیوری شواہد اور ٹریس ایبلٹی کے لیے کنٹرولڈ ورک اسپیس۔',
    hi: 'प्रोजेक्ट, मटेरियल रिक्वेस्ट, डिलीवरी प्रमाण और ट्रेसबिलिटी के लिए नियंत्रित कार्यक्षेत्र।',
  );
  static const secureAccess = TranslatableString(
    en: 'Secure access',
    ar: 'وصول آمن',
    ur: 'محفوظ رسائی',
    hi: 'सुरक्षित पहुँच',
  );
  static const companyEmail = TranslatableString(
    en: 'Company email',
    ar: 'البريد الإلكتروني للشركة',
    ur: 'کمپنی ای میل',
    hi: 'कंपनी ईमेल',
  );
  static const companyEmailHint = TranslatableString(
    en: 'name@company.com',
    ar: 'name@company.com',
    ur: 'name@company.com',
    hi: 'name@company.com',
  );
  static const passwordHint = TranslatableString(
    en: 'Enter password',
    ar: 'أدخل كلمة المرور',
    ur: 'پاس ورڈ درج کریں',
    hi: 'पासवर्ड दर्ज करें',
  );
  static const protectedSession = TranslatableString(
    en: 'Your session and operational records are protected.',
    ar: 'جلستك وسجلاتك التشغيلية محمية.',
    ur: 'آپ کا سیشن اور آپریشنل ریکارڈ محفوظ ہیں۔',
    hi: 'आपका सत्र और ऑपरेशनल रिकॉर्ड सुरक्षित हैं।',
  );
  static const accountabilityNotice = TranslatableString(
    en: 'Every BOQ, request and approval records the responsible user and time.',
    ar: 'يسجل كل جدول كميات وطلب وموافقة المستخدم المسؤول والوقت.',
    ur: 'ہر BOQ، درخواست اور منظوری ذمہ دار صارف اور وقت ریکارڈ کرتی ہے۔',
    hi: 'हर BOQ, अनुरोध और अनुमोदन में जिम्मेदार उपयोगकर्ता और समय दर्ज होता है।',
  );
  static const projects = TranslatableString(
    en: 'Projects',
    ar: 'المشاريع',
    ur: 'پراجیکٹس',
    hi: 'परियोजनाएँ',
  );
  static const documentControl = TranslatableString(
    en: 'Document control',
    ar: 'ضبط المستندات',
    ur: 'دستاویز کنٹرول',
    hi: 'दस्तावेज़ नियंत्रण',
  );
  static const procurement = TranslatableString(
    en: 'Procurement',
    ar: 'المشتريات',
    ur: 'پروکیورمنٹ',
    hi: 'खरीद',
  );
  static const overview = TranslatableString(
    en: 'Overview',
    ar: 'نظرة عامة',
    ur: 'جائزہ',
    hi: 'अवलोकन',
  );
  static const materialRequests = TranslatableString(
    en: 'Material Requests',
    ar: 'طلبات المواد',
    ur: 'مواد کی درخواستیں',
    hi: 'सामग्री अनुरोध',
  );
  static const requestsCompact = TranslatableString(
    en: 'Requests',
    ar: 'الطلبات',
    ur: 'درخواستیں',
    hi: 'अनुरोध',
  );
  static const browseInventory = TranslatableString(
    en: 'Browse / Inventory',
    ar: 'استعراض / المخزون',
    ur: 'براؤز / انوینٹری',
    hi: 'ब्राउज़ / इन्वेंटरी',
  );
  static const procurementGreeting = TranslatableString(
    en: 'Good evening · Procurement',
    ar: 'مساء الخير · المشتريات',
    ur: 'شام بخیر · پروکیورمنٹ',
    hi: 'शुभ संध्या · खरीद',
  );
  static const procurementHero = TranslatableString(
    en: 'Arrange, approve and dispatch without over-supplying.',
    ar: 'رتب واعتمد وأرسل دون زيادة في التوريد.',
    ur: 'ضرورت سے زیادہ سپلائی کے بغیر ترتیب دیں، منظور کریں اور ڈسپیچ کریں۔',
    hi: 'अधिक आपूर्ति किए बिना व्यवस्थित करें, अनुमोदित करें और डिस्पैच करें।',
  );
  static const procurementHeroDescription = TranslatableString(
    en: 'Projects are view-only. Procurement works from the Engineer’s Material Request, records unavailable items clearly, and dispatches only the quantities approved.',
    ar: 'المشاريع للعرض فقط. تعمل المشتريات من طلب مواد المهندس وتسجل العناصر غير المتاحة بوضوح وترسل الكميات المعتمدة فقط.',
    ur: 'پراجیکٹس صرف دیکھنے کے لیے ہیں۔ پروکیورمنٹ انجینئر کی میٹیریل ریکویسٹ سے کام کرتی ہے، ناقابل فراہمی آئٹمز واضح کرتی ہے اور صرف منظور شدہ مقدار ڈسپیچ کرتی ہے۔',
    hi: 'प्रोजेक्ट केवल देखने योग्य हैं। खरीद इंजीनियर के सामग्री अनुरोध से काम करता है, अनुपलब्ध वस्तुओं को स्पष्ट रूप से दर्ज करता है और केवल स्वीकृत मात्रा भेजता है।',
  );
  static const viewProjects = TranslatableString(
    en: 'View Projects',
    ar: 'عرض المشاريع',
    ur: 'پراجیکٹس دیکھیں',
    hi: 'प्रोजेक्ट देखें',
  );
  static const newToArrange = TranslatableString(
    en: 'New to arrange',
    ar: 'جديد للترتيب',
    ur: 'ترتیب کے لیے نئی',
    hi: 'व्यवस्था के लिए नया',
  );
  static const readyToDispatch = TranslatableString(
    en: 'Ready to dispatch',
    ar: 'جاهز للإرسال',
    ur: 'ڈسپیچ کے لیے تیار',
    hi: 'डिस्पैच के लिए तैयार',
  );
  static const lowOutOfStock = TranslatableString(
    en: 'Low / out of stock',
    ar: 'مخزون منخفض / نفد',
    ur: 'کم / ختم شدہ اسٹاک',
    hi: 'कम / स्टॉक में नहीं',
  );
  static const request = TranslatableString(
    en: 'Request',
    ar: 'الطلب',
    ur: 'درخواست',
    hi: 'अनुरोध',
  );
  static const requestStepDescription = TranslatableString(
    en: 'Engineer submits',
    ar: 'يقدم المهندس',
    ur: 'انجینئر جمع کراتا ہے',
    hi: 'इंजीनियर जमा करता है',
  );
  static const arrange = TranslatableString(
    en: 'Arrange',
    ar: 'ترتيب',
    ur: 'ترتیب',
    hi: 'व्यवस्थित करें',
  );
  static const arrangeStepDescription = TranslatableString(
    en: 'Supply or mark unavailable',
    ar: 'وفر أو حدد غير المتاح',
    ur: 'سپلائی کریں یا ناقابل فراہمی نشان لگائیں',
    hi: 'आपूर्ति करें या अनुपलब्ध चिह्नित करें',
  );
  static const approve = TranslatableString(
    en: 'Approve',
    ar: 'اعتماد',
    ur: 'منظور کریں',
    hi: 'स्वीकृत करें',
  );
  static const approveStepDescription = TranslatableString(
    en: 'Project Engineer approves request',
    ar: 'يعتمد مهندس المشروع الطلب',
    ur: 'پراجیکٹ انجینئر درخواست منظور کرتا ہے',
    hi: 'प्रोजेक्ट इंजीनियर अनुरोध स्वीकृत करता है',
  );
  static const dispatch = TranslatableString(
    en: 'Dispatch',
    ar: 'إرسال',
    ur: 'ڈسپیچ',
    hi: 'डिस्पैच',
  );
  static const dispatchStepDescription = TranslatableString(
    en: 'Only approved quantities',
    ar: 'الكميات المعتمدة فقط',
    ur: 'صرف منظور شدہ مقدار',
    hi: 'केवल स्वीकृत मात्रा',
  );
  static const receipt = TranslatableString(
    en: 'Receipt',
    ar: 'استلام',
    ur: 'وصولی',
    hi: 'प्राप्ति',
  );
  static const receiptStepDescription = TranslatableString(
    en: 'Project team confirms',
    ar: 'يؤكد فريق المشروع',
    ur: 'پراجیکٹ ٹیم تصدیق کرتی ہے',
    hi: 'प्रोजेक्ट टीम पुष्टि करती है',
  );
  static const newRequests = TranslatableString(
    en: 'New requests',
    ar: 'طلبات جديدة',
    ur: 'نئی درخواستیں',
    hi: 'नए अनुरोध',
  );
  static const newRequestsDescription = TranslatableString(
    en: 'Need Procurement arrangement',
    ar: 'تحتاج إلى ترتيب المشتريات',
    ur: 'پروکیورمنٹ انتظام درکار ہے',
    hi: 'खरीद व्यवस्था आवश्यक है',
  );
  static const engineerReview = TranslatableString(
    en: 'Engineer review',
    ar: 'مراجعة المهندس',
    ur: 'انجینئر ریویو',
    hi: 'इंजीनियर समीक्षा',
  );
  static const engineerReviewDescription = TranslatableString(
    en: 'Waiting for Project Engineer',
    ar: 'بانتظار مهندس المشروع',
    ur: 'پراجیکٹ انجینئر کا انتظار ہے',
    hi: 'प्रोजेक्ट इंजीनियर की प्रतीक्षा है',
  );
  static const approved = TranslatableString(
    en: 'Approved',
    ar: 'معتمد',
    ur: 'منظور شدہ',
    hi: 'स्वीकृत',
  );
  static const approvedDescription = TranslatableString(
    en: 'Ready for controlled dispatch',
    ar: 'جاهز للإرسال المتحكم به',
    ur: 'کنٹرولڈ ڈسپیچ کے لیے تیار',
    hi: 'नियंत्रित डिस्पैच के लिए तैयार',
  );
  static const awaitingReceipt = TranslatableString(
    en: 'Awaiting receipt',
    ar: 'بانتظار الاستلام',
    ur: 'وصولی کا انتظار',
    hi: 'प्राप्ति की प्रतीक्षा',
  );
  static const awaitingReceiptDescription = TranslatableString(
    en: 'Sent to project team',
    ar: 'أرسلت إلى فريق المشروع',
    ur: 'پراجیکٹ ٹیم کو بھیج دیا گیا',
    hi: 'प्रोजेक्ट टीम को भेजा गया',
  );
  static const needsProcurementAction = TranslatableString(
    en: 'Needs Procurement Action',
    ar: 'يتطلب إجراء المشتريات',
    ur: 'پروکیورمنٹ کی کارروائی درکار ہے',
    hi: 'खरीद कार्रवाई आवश्यक है',
  );
  static const procurementActionDescription = TranslatableString(
    en: 'Only requests that Procurement can act on are shown here.',
    ar: 'تظهر هنا فقط الطلبات التي يمكن للمشتريات التصرف بشأنها.',
    ur: 'یہاں صرف وہ درخواستیں دکھائی جاتی ہیں جن پر پروکیورمنٹ کارروائی کر سکتی ہے۔',
    hi: 'यहां केवल वे अनुरोध दिखाए जाते हैं जिन पर खरीद कार्रवाई कर सकता है।',
  );
  static const viewAllRequests = TranslatableString(
    en: 'View All Requests',
    ar: 'عرض كل الطلبات',
    ur: 'تمام درخواستیں دیکھیں',
    hi: 'सभी अनुरोध देखें',
  );
  static const noProcurementAction = TranslatableString(
    en: 'Nothing needs Procurement action',
    ar: 'لا شيء يحتاج إلى إجراء المشتريات',
    ur: 'کسی چیز کو پروکیورمنٹ کی کارروائی درکار نہیں',
    hi: 'किसी चीज़ को खरीद कार्रवाई की आवश्यकता नहीं है',
  );
  static const requestsUnavailable = TranslatableString(
    en: 'Material Requests are unavailable right now.',
    ar: 'طلبات المواد غير متاحة حاليًا.',
    ur: 'میٹیریل ریکویسٹس فی الحال دستیاب نہیں ہیں۔',
    hi: 'सामग्री अनुरोध अभी उपलब्ध नहीं हैं।',
  );
  static const dispatches = TranslatableString(
    en: 'Dispatches',
    ar: 'الإرساليات',
    ur: 'ڈسپیچز',
    hi: 'डिस्पैच',
  );
  static const materialReturns = TranslatableString(
    en: 'Material Returns',
    ar: 'مرتجعات المواد',
    ur: 'مواد کی واپسی',
    hi: 'सामग्री वापसी',
  );
  static const returnsCompact = TranslatableString(
    en: 'Returns',
    ar: 'المرتجعات',
    ur: 'واپسی',
    hi: 'वापसी',
  );
  static const ductCompact = TranslatableString(
    en: 'Duct',
    ar: 'المجرى',
    ur: 'ڈکٹ',
    hi: 'डक्ट',
  );
  static const espCompact = TranslatableString(
    en: 'ESP',
    ar: 'ESP',
    ur: 'ESP',
    hi: 'ESP',
  );
  static const engineeringTools = TranslatableString(
    en: 'Engineering tools',
    ar: 'أدوات الهندسة',
    ur: 'انجینئرنگ ٹولز',
    hi: 'इंजीनियरिंग टूल्स',
  );
  static const administration = TranslatableString(
    en: 'Administration',
    ar: 'الإدارة',
    ur: 'انتظامیہ',
    hi: 'प्रशासन',
  );
  static const configuration = TranslatableString(
    en: 'Configuration',
    ar: 'الإعدادات',
    ur: 'کنفیگریشن',
    hi: 'कॉन्फ़िगरेशन',
  );
  static const rentalProperties = TranslatableString(
    en: 'Rental Properties',
    ar: 'العقارات المؤجرة',
    ur: 'رینٹل پراپرٹیز',
    hi: 'किराये की संपत्तियाँ',
  );
  static const userManagement = TranslatableString(
    en: 'User Management',
    ar: 'إدارة المستخدمين',
    ur: 'صارف مینجمنٹ',
    hi: 'उपयोगकर्ता प्रबंधन',
  );
  static const auditTrail = TranslatableString(
    en: 'Audit Trail',
    ar: 'سجل التدقيق',
    ur: 'آڈٹ ٹریل',
    hi: 'ऑडिट ट्रेल',
  );
  static const viewOnly = TranslatableString(
    en: 'View only',
    ar: 'للعرض فقط',
    ur: 'صرف دیکھنے کے لیے',
    hi: 'केवल देखें',
  );
  static const ductSizer = TranslatableString(
    en: 'Duct Sizer',
    ar: 'حاسبة مجرى الهواء',
    ur: 'ڈکٹ سائزَر',
    hi: 'डक्ट साइज़र',
  );
  static const espCalculator = TranslatableString(
    en: 'ESP Calculator',
    ar: 'حاسبة الضغط الساكن الخارجي',
    ur: 'ای ایس پی کیلکولیٹر',
    hi: 'ईएसपी कैलकुलेटर',
  );
  static const account = TranslatableString(
    en: 'Account',
    ar: 'الحساب',
    ur: 'اکاؤنٹ',
    hi: 'खाता',
  );
  static const selectedRequestRequired = TranslatableString(
    en: 'Select a material request to continue.',
    ar: 'اختر طلب مواد للمتابعة.',
    ur: 'جاری رکھنے کے لیے میٹیریل ریکویسٹ منتخب کریں۔',
    hi: 'जारी रखने के लिए मटेरियल रिक्वेस्ट चुनें।',
  );
  static const integrationPending = TranslatableString(
    en: 'Available in the next Yorks V1 integration.',
    ar: 'متاح في تكامل Yorks V1 القادم.',
    ur: 'اگلی Yorks V1 انٹیگریشن میں دستیاب ہوگا۔',
    hi: 'अगले Yorks V1 इंटीग्रेशन में उपलब्ध होगा।',
  );
  static const showPassword = TranslatableString(
    en: 'Show password',
    ar: 'إظهار كلمة المرور',
    ur: 'پاس ورڈ دکھائیں',
    hi: 'पासवर्ड दिखाएँ',
  );
  static const hidePassword = TranslatableString(
    en: 'Hide password',
    ar: 'إخفاء كلمة المرور',
    ur: 'پاس ورڈ چھپائیں',
    hi: 'पासवर्ड छिपाएँ',
  );
  static const emailRequired = TranslatableString(
    en: 'Company email is required.',
    ar: 'البريد الإلكتروني للشركة مطلوب.',
    ur: 'کمپنی ای میل ضروری ہے۔',
    hi: 'कंपनी ईमेल आवश्यक है।',
  );
  static const emailInvalid = TranslatableString(
    en: 'Enter a valid company email.',
    ar: 'أدخل بريد شركة صالحاً.',
    ur: 'درست کمپنی ای میل درج کریں۔',
    hi: 'मान्य कंपनी ईमेल दर्ज करें।',
  );
  static const passwordRequired = TranslatableString(
    en: 'Password is required.',
    ar: 'كلمة المرور مطلوبة.',
    ur: 'پاس ورڈ ضروری ہے۔',
    hi: 'पासवर्ड आवश्यक है।',
  );
  static const invalidCredentials = TranslatableString(
    en: 'Invalid company email or password.',
    ar: 'البريد الإلكتروني للشركة أو كلمة المرور غير صحيحة.',
    ur: 'کمپنی ای میل یا پاس ورڈ غلط ہے۔',
    hi: 'कंपनी ईमेल या पासवर्ड गलत है।',
  );
  static const accountDeactivated = TranslatableString(
    en: 'This account is deactivated. Contact your administrator.',
    ar: 'تم تعطيل هذا الحساب. اتصل بالمسؤول.',
    ur: 'یہ اکاؤنٹ غیر فعال ہے۔ اپنے ایڈمنسٹریٹر سے رابطہ کریں۔',
    hi: 'यह खाता निष्क्रिय है। अपने व्यवस्थापक से संपर्क करें।',
  );
  static const emailNotConfirmed = TranslatableString(
    en: 'Confirm your company email before signing in.',
    ar: 'أكد بريد الشركة الإلكتروني قبل تسجيل الدخول.',
    ur: 'سائن اِن کرنے سے پہلے اپنے کمپنی ای میل کی تصدیق کریں۔',
    hi: 'साइन इन करने से पहले अपने कंपनी ईमेल की पुष्टि करें।',
  );
  static const rateLimited = TranslatableString(
    en: 'Too many sign-in attempts. Please wait a moment and try again.',
    ar: 'تمت محاولات تسجيل دخول كثيرة. يرجى الانتظار قليلاً ثم المحاولة مرة أخرى.',
    ur: 'سائن اِن کی بہت زیادہ کوششیں ہو چکی ہیں۔ تھوڑی دیر بعد دوبارہ کوشش کریں۔',
    hi: 'बहुत अधिक साइन-इन प्रयास हुए। थोड़ा इंतजार करें और फिर कोशिश करें।',
  );
  static const accountSetupRequired = TranslatableString(
    en: 'This account is not ready for the Yorks workspace. Contact your administrator.',
    ar: 'هذا الحساب غير جاهز لمساحة عمل Yorks. اتصل بالمسؤول.',
    ur: 'یہ اکاؤنٹ Yorks ورک اسپیس کے لیے تیار نہیں ہے۔ اپنے ایڈمنسٹریٹر سے رابطہ کریں۔',
    hi: 'यह खाता Yorks कार्यस्थान के लिए तैयार नहीं है। अपने व्यवस्थापक से संपर्क करें।',
  );
  static const serverUnreachable = TranslatableString(
    en: 'Cannot reach the server. Check your connection and try again.',
    ar: 'يتعذر الوصول إلى الخادم. تحقق من الاتصال وحاول مرة أخرى.',
    ur: 'سرور تک رسائی ممکن نہیں۔ کنکشن چیک کریں اور دوبارہ کوشش کریں۔',
    hi: 'सर्वर तक पहुँचना संभव नहीं है। कनेक्शन जाँचें और फिर प्रयास करें।',
  );
}
