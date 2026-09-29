import 'app_language.dart';

/// All UI string translations keyed by label ID.
///
/// English is always the primary language shown.
/// Secondary text is selected by [AppLanguage].
abstract final class AppStrings {
  // ─── Navigation ───────────────────────────────────────────
  static const dashboard = TranslatableString(
    en: 'Dashboard',
    ar: 'لوحة القيادة',
    ur: 'ڈیش بورڈ',
    hi: 'डैशबोर्ड',
  );
  static const inventory = TranslatableString(
    en: 'Inventory',
    ar: 'المخزون',
    ur: 'انوینٹری',
    hi: 'इन्वेंटरी',
  );
  static const transactions = TranslatableString(
    en: 'Transactions',
    ar: 'المعاملات',
    ur: 'لین دین',
    hi: 'लेन-देन',
  );
  static const settings = TranslatableString(
    en: 'Settings',
    ar: 'الإعدادات',
    ur: 'ترتیبات',
    hi: 'सेटिंग्स',
  );
  static const alertCenter = TranslatableString(
    en: 'Alert Center',
    ar: 'مركز التنبيهات',
    ur: 'الرٹ سینٹر',
    hi: 'अलर्ट सेंटर',
  );
  static const recentUpdates = TranslatableString(
    en: 'Recent Updates',
    ar: 'التحديثات الأخيرة',
    ur: 'حالیہ اپڈیٹس',
    hi: 'हालिया अपडेट',
  );

  // ─── Navigation (IA restructure) ──────────────────────────
  static const home = TranslatableString(
    en: 'Home',
    ar: 'الرئيسية',
    ur: 'ہوم',
    hi: 'होम',
  );
  static const more = TranslatableString(
    en: 'More',
    ar: 'المزيد',
    ur: 'مزید',
    hi: 'अधिक',
  );
  static const materialsSubtitle = TranslatableString(
    en: 'Stock, procurement & requests',
    ar: 'المخزون والمشتريات والطلبات',
    ur: 'اسٹاک، خریداری اور درخواستیں',
    hi: 'स्टॉक, खरीद और अनुरोध',
  );
  static const returnsAndReceipts = TranslatableString(
    en: 'Returns & receipts',
    ar: 'المرتجعات والإيصالات',
    ur: 'واپسی اور رسیدیں',
    hi: 'वापसी और रसीदें',
  );
  static const returnsAndReceiptsHint = TranslatableString(
    en: 'Stock in & material returns',
    ar: 'إدخال المخزون ومرتجعات المواد',
    ur: 'اسٹاک اِن اور مواد کی واپسی',
    hi: 'स्टॉक इन और सामग्री वापसी',
  );
  static const adminSettings = TranslatableString(
    en: 'Admin · Settings',
    ar: 'الإدارة · الإعدادات',
    ur: 'ایڈمن · ترتیبات',
    hi: 'एडमिन · सेटिंग्स',
  );
  static const adminSettingsSubtitle = TranslatableString(
    en: 'Users, access & system',
    ar: 'المستخدمون والوصول والنظام',
    ur: 'صارفین، رسائی اور سسٹم',
    hi: 'उपयोगकर्ता, एक्सेस और सिस्टम',
  );
  static const administration = TranslatableString(
    en: 'Administration',
    ar: 'الإدارة',
    ur: 'انتظامیہ',
    hi: 'प्रशासन',
  );
  static const system = TranslatableString(
    en: 'System',
    ar: 'النظام',
    ur: 'سسٹم',
    hi: 'सिस्टम',
  );
  static const accessRoles = TranslatableString(
    en: 'Access & Roles',
    ar: 'الوصول والأدوار',
    ur: 'رسائی اور کردار',
    hi: 'एक्सेस और भूमिकाएँ',
  );
  static const accessRolesHint = TranslatableString(
    en: 'Who can see & do what',
    ar: 'من يمكنه الرؤية والتنفيذ',
    ur: 'کون کیا دیکھ اور کر سکتا ہے',
    hi: 'कौन क्या देख और कर सकता है',
  );
  static const dataSync = TranslatableString(
    en: 'Data & Sync',
    ar: 'البيانات والمزامنة',
    ur: 'ڈیٹا اور سنک',
    hi: 'डेटा और सिंक',
  );
  static const dataSyncHint = TranslatableString(
    en: 'Offline queue & status',
    ar: 'قائمة الانتظار والحالة دون اتصال',
    ur: 'آف لائن قطار اور حالت',
    hi: 'ऑफ़लाइन क़तार और स्थिति',
  );
  static const allSynced = TranslatableString(
    en: 'All synced',
    ar: 'تمت المزامنة',
    ur: 'سب سنک ہو گیا',
    hi: 'सब सिंक हो गया',
  );
  static const discardRequestTitle = TranslatableString(
    en: 'Discard request?',
    ar: 'تجاهل الطلب؟',
    ur: 'درخواست رد کریں؟',
    hi: 'अनुरोध छोड़ें?',
  );
  static const discardRequestBody = TranslatableString(
    en: 'The items you added will be removed.',
    ar: 'سيتم إزالة العناصر التي أضفتها.',
    ur: 'آپ کے شامل کردہ آئٹمز ہٹا دیے جائیں گے۔',
    hi: 'आपके जोड़े गए आइटम हटा दिए जाएंगे।',
  );
  static const keepEditing = TranslatableString(
    en: 'Keep editing',
    ar: 'متابعة التعديل',
    ur: 'ترمیم جاری رکھیں',
    hi: 'संपादन जारी रखें',
  );
  static const discard = TranslatableString(
    en: 'Discard',
    ar: 'تجاهل',
    ur: 'رد کریں',
    hi: 'छोड़ें',
  );

  // ─── Dashboard ────────────────────────────────────────────
  static const totalStockValue = TranslatableString(
    en: 'Total Stock Value',
    ar: 'إجمالي قيمة المخزون',
    ur: 'کل اسٹاک کی قیمت',
    hi: 'कुल स्टॉक मूल्य',
  );
  static const materials = TranslatableString(
    en: 'Materials',
    ar: 'المواد',
    ur: 'مواد',
    hi: 'सामग्री',
  );
  static const recentActivity = TranslatableString(
    en: 'Recent Activity',
    ar: 'النشاط الأخير',
    ur: 'حالیہ سرگرمی',
    hi: 'हालिया गतिविधि',
  );
  static const noRecentActivity = TranslatableString(
    en: 'No recent activity',
    ar: 'لا يوجد نشاط حديث',
    ur: 'کوئی حالیہ سرگرمی نہیں',
    hi: 'कोई हालिया गतिविधि नहीं',
  );
  static const viewAll = TranslatableString(
    en: 'View all',
    ar: 'عرض الكل',
    ur: 'سب دیکھیں',
    hi: 'सभी देखें',
  );
  static const requestsThisWeek = TranslatableString(
    en: 'Requests this week',
    ar: 'الطلبات هذا الأسبوع',
    ur: 'اس ہفتے کی درخواستیں',
    hi: 'इस सप्ताह के अनुरोध',
  );
  static const vsLastWeek = TranslatableString(
    en: 'vs last week',
    ar: 'مقارنة بالأسبوع الماضي',
    ur: 'پچھلے ہفتے کے مقابلے',
    hi: 'पिछले सप्ताह की तुलना में',
  );
  static const noDataYet = TranslatableString(
    en: 'No data yet',
    ar: 'لا توجد بيانات بعد',
    ur: 'ابھی تک کوئی ڈیٹا نہیں',
    hi: 'अभी तक कोई डेटा नहीं',
  );

  // ─── Inventory ────────────────────────────────────────────
  static const noMaterialsAdded = TranslatableString(
    en: 'No materials added yet',
    ar: 'لم تتم إضافة مواد بعد',
    ur: 'ابھی تک کوئی مواد شامل نہیں کیا گیا',
    hi: 'अभी तक कोई सामग्री नहीं जोड़ी गई',
  );
  static const addMaterial = TranslatableString(
    en: 'Add Material',
    ar: 'إضافة مادة',
    ur: 'مواد شامل کریں',
    hi: 'सामग्री जोड़ें',
  );
  static const tapToAddFirst = TranslatableString(
    en: 'Tap + to add your first material',
    ar: 'اضغط + لإضافة أول مادة',
    ur: 'پہلا مواد شامل کرنے کے لیے + دبائیں',
    hi: 'पहली सामग्री जोड़ने के लिए + दबाएं',
  );

  // ─── Transactions ─────────────────────────────────────────
  static const noTransactions = TranslatableString(
    en: 'No transactions recorded',
    ar: 'لم يتم تسجيل معاملات',
    ur: 'کوئی لین دین ریکارڈ نہیں ہوا',
    hi: 'कोई लेन-देन दर्ज नहीं',
  );
  static const transactionsWillAppear = TranslatableString(
    en: 'Transactions will appear here once you start recording',
    ar: 'ستظهر المعاملات هنا بمجرد بدء التسجيل',
    ur: 'ریکارڈنگ شروع کرنے پر لین دین یہاں ظاہر ہوں گے',
    hi: 'रिकॉर्डिंग शुरू करने पर लेन-देन यहां दिखाई देंगे',
  );

  // ─── Settings ─────────────────────────────────────────────
  static const secondaryLanguage = TranslatableString(
    en: 'Secondary Language',
    ar: 'اللغة الثانوية',
    ur: 'ثانوی زبان',
    hi: 'द्वितीयक भाषा',
  );
  static const currency = TranslatableString(
    en: 'Currency',
    ar: 'العملة',
    ur: 'کرنسی',
    hi: 'मुद्रा',
  );
  static const appearance = TranslatableString(
    en: 'Appearance',
    ar: 'المظهر',
    ur: 'ظاہری شکل',
    hi: 'दिखावट',
  );
  static const backupSync = TranslatableString(
    en: 'Backup & Sync',
    ar: 'النسخ الاحتياطي والمزامنة',
    ur: 'بیک اپ اور سنک',
    hi: 'बैकअप और सिंक',
  );
  static const about = TranslatableString(
    en: 'About',
    ar: 'حول',
    ur: 'ایپ کے بارے میں',
    hi: 'के बारे में',
  );
  static const logout = TranslatableString(
    en: 'Logout',
    ar: 'تسجيل الخروج',
    ur: 'لاگ آؤٹ',
    hi: 'लॉगआउट',
  );
  static const logoutConfirmBody = TranslatableString(
    en: 'Are you sure you want to logout?',
    ar: 'هل أنت متأكد أنك تريد تسجيل الخروج؟',
    ur: 'کیا آپ واقعی لاگ آؤٹ کرنا چاہتے ہیں؟',
    hi: 'क्या आप वाकई लॉगआउट करना चाहते हैं?',
  );
  static const enterAtLeast3Chars = TranslatableString(
    en: 'Enter at least 3 characters',
    ar: 'أدخل 3 أحرف على الأقل',
    ur: 'کم از کم 3 حروف درج کریں',
    hi: 'कम से कम 3 अक्षर दर्ज करें',
  );
  static const noProjectsYet = TranslatableString(
    en: 'No projects yet',
    ar: 'لا توجد مشاريع بعد',
    ur: 'ابھی کوئی پروجیکٹ نہیں',
    hi: 'अभी कोई परियोजना नहीं',
  );
  static const addProjectToBegin = TranslatableString(
    en: 'Add a project to begin tracking requests and dispatches.',
    ar: 'أضف مشروعاً لبدء تتبع الطلبات والإرساليات.',
    ur: 'درخواستوں اور ترسیل کو ٹریک کرنے کے لیے ایک پروجیکٹ شامل کریں۔',
    hi: 'अनुरोध व प्रेषण ट्रैक करना शुरू करने हेतु एक परियोजना जोड़ें।',
  );
  static const appLock = TranslatableString(
    en: 'App lock',
    ar: 'قفل التطبيق',
    ur: 'ایپ لاک',
    hi: 'ऐप लॉक',
  );
  static const light = TranslatableString(
    en: 'Light',
    ar: 'فاتح',
    ur: 'ہلکا',
    hi: 'हल्का',
  );

  // ─── Onboarding ───────────────────────────────────────────
  static const welcomeTo = TranslatableString(
    en: 'Welcome to Yorks AC. & Ref.',
    ar: 'مرحباً بك في Yorks AC. & Ref.',
    ur: 'Yorks AC. & Ref. میں خوش آمدید',
    hi: 'Yorks AC. & Ref. में आपका स्वागत है',
  );
  static const selectLanguage = TranslatableString(
    en: 'SELECT LANGUAGE',
    ar: 'اختر اللغة',
    ur: 'زبان منتخب کریں',
    hi: 'भाषा चुनें',
  );
  static const getStarted = TranslatableString(
    en: 'Get Started',
    ar: 'ابدأ الآن',
    ur: 'شروع کریں',
    hi: 'शुरू करें',
  );
  static const dataSyncReady = TranslatableString(
    en: 'Data Sync Ready',
    ar: 'مزامنة البيانات جاهزة',
    ur: 'ڈیٹا کی ہم آہنگی تیار ہے',
    hi: 'डेटा सिंक तैयार',
  );
  static const dataSyncDesc = TranslatableString(
    en: 'Your inventory preferences will be synced across all architectural ledgers in your warehouse cluster.',
    ar: 'ستتم مزامنة تفضيلات المخزون عبر جميع دفاتر المعمار في مجموعة المستودعات الخاصة بك.',
    ur: 'آپ کی انوینٹری ترجیحات آپ کے گودام کلسٹر میں تمام معماری لیجرز میں ہم آہنگ ہوں گی۔',
    hi: 'आपकी इन्वेंटरी प्राथमिकताएं आपके वेयरहाउस क्लस्टर के सभी आर्किटेक्चरल लेजर में सिंक की जाएंगी।',
  );

  // ─── Login ───────────────────────────────────────────────
  static const login = TranslatableString(
    en: 'Login',
    ar: 'سجل الدخول',
    ur: 'لاگ ان کریں',
    hi: 'लॉगिन करें',
  );
  static const emailAddress = TranslatableString(
    en: 'Email Address',
    ar: 'البريد الإلكتروني',
    ur: 'ای میل ایڈریس',
    hi: 'ईमेल पता',
  );
  static const password = TranslatableString(
    en: 'Password',
    ar: 'كلمة المرور',
    ur: 'پاس ورڈ',
    hi: 'पासवर्ड',
  );
  static const forgotPassword = TranslatableString(
    en: 'Forgot Password?',
    ar: 'هل نسيت كلمة المرور؟',
    ur: 'پاس ورڈ بھول گئے؟',
    hi: 'पासवर्ड भूल गए?',
  );
  static const accessSystem = TranslatableString(
    en: 'Access System',
    ar: 'دخول النظام',
    ur: 'سسٹم تک رسائی',
    hi: 'सिस्टम एक्सेस',
  );
  static const secureIndustrialEnvironment = TranslatableString(
    en: 'SECURE INDUSTRIAL ENVIRONMENT',
    ar: 'بيئة صناعية آمنة',
    ur: 'محفوظ صنعتی ماحول',
    hi: 'सुरक्षित औद्योगिक वातावरण',
  );
  static const signIn = TranslatableString(
    en: 'Sign In',
    ar: 'سائن ان کریں',
    ur: 'سائن ان کریں',
    hi: 'साइन इन करें',
  );
  static const rememberMe = TranslatableString(
    en: 'Remember Me',
    ar: 'تذكرني',
    ur: 'مجھے یاد رکھیں',
    hi: 'मुझे याद रखें',
  );
  static const contactSupport = TranslatableString(
    en: 'Contact Support',
    ar: 'اتصل بالدعم',
    ur: 'سپورٹ سے رابطہ کریں',
    hi: 'सहायता से संपर्क करें',
  );

  // ─── Splash ───────────────────────────────────────────────
  static const architecturalLedger = TranslatableString(
    en: 'THE ARCHITECTURAL LEDGER',
    ar: 'السجل المعماري',
    ur: 'معماری لیجر',
    hi: 'वास्तुशिल्प खाता',
  );

  // ─── Add Material ───────────────────────────────────────────
  static const addNewMaterial = TranslatableString(
    en: 'Add New Material',
    ar: 'إضافة مادة جديدة',
    ur: 'نیا مواد شامل کریں',
    hi: 'नई सामग्री जोड़ें',
  );
  static const materialName = TranslatableString(
    en: 'Material Name',
    ar: 'اسم المادة',
    ur: 'مواد کا نام',
    hi: 'सामग्री का नाम',
  );
  static const materialNameUrdu = TranslatableString(
    en: 'Name in Secondary Language',
    ar: 'الاسم باللغة الثانوية',
    ur: 'ثانوی زبان میں نام',
    hi: 'द्वितीयक भाषा में नाम',
  );
  static const category = TranslatableString(
    en: 'Category',
    ar: 'الفئة',
    ur: 'زمرہ',
    hi: 'श्रेणी',
  );
  static const unit = TranslatableString(
    en: 'Unit',
    ar: 'الوحدة',
    ur: 'اکائی',
    hi: 'इकाई',
  );
  static const quantity = TranslatableString(
    en: 'Quantity',
    ar: 'الكمية',
    ur: 'مقدار',
    hi: 'मात्रा',
  );
  static const unitPrice = TranslatableString(
    en: 'Unit Price',
    ar: 'سعر الوحدة',
    ur: 'فی اکائی قیمت',
    hi: 'इकाई मूल्य',
  );
  static const reserved = TranslatableString(
    en: 'Reserved',
    ar: 'محجوز',
    ur: 'مختص',
    hi: 'आरक्षित',
  );
  static const available = TranslatableString(
    en: 'Available',
    ar: 'متاح',
    ur: 'دستیاب',
    hi: 'उपलब्ध',
  );
  static const stockDetails = TranslatableString(
    en: 'Stock details',
    ar: 'تفاصيل المخزون',
    ur: 'اسٹاک تفصیلات',
    hi: 'स्टॉक विवरण',
  );
  static const brandSupplier = TranslatableString(
    en: 'Brand / Supplier',
    ar: 'العلامة / المورّد',
    ur: 'برانڈ / سپلائر',
    hi: 'ब्रांड / आपूर्तिकर्ता',
  );

  // ─── Procurement workspace (plan review + dispatch) ───────────
  static const procurement = TranslatableString(
    en: 'Procurement',
    ar: 'المشتريات',
    ur: 'پروکیورمنٹ',
    hi: 'खरीद',
  );
  static const procurementSubtitle = TranslatableString(
    en: 'Arrange plans & dispatch site requests',
    ar: 'ترتيب الخطط وصرف طلبات الموقع',
    ur: 'پلان ترتیب دیں اور سائٹ کی درخواستیں روانہ کریں',
    hi: 'योजनाएँ व्यवस्थित करें और साइट अनुरोध भेजें',
  );
  static const queueClear = TranslatableString(
    en: 'Nothing here — all clear',
    ar: 'لا شيء هنا — كل شيء جاهز',
    ur: 'یہاں کچھ نہیں — سب صاف',
    hi: 'यहाँ कुछ नहीं — सब साफ़',
  );
  static const needYourAttention = TranslatableString(
    en: 'need your attention',
    ar: 'تحتاج إلى انتباهك',
    ur: 'آپ کی توجہ درکار ہے',
    hi: 'आपके ध्यान की आवश्यकता',
  );
  static const awaitingAction = TranslatableString(
    en: 'Awaiting you',
    ar: 'بانتظارك',
    ur: 'آپ کے منتظر',
    hi: 'आपकी प्रतीक्षा में',
  );
  static const notifNewRequestTitle = TranslatableString(
    en: 'New material request',
    ar: 'طلب مواد جديد',
    ur: 'نئی مٹیریل درخواست',
    hi: 'नया सामग्री अनुरोध',
  );
  static const notifNewPlanTitle = TranslatableString(
    en: 'New material plan to review',
    ar: 'خطة مواد جديدة للمراجعة',
    ur: 'جائزے کے لیے نیا مٹیریل پلان',
    hi: 'समीक्षा हेतु नई सामग्री योजना',
  );
  static const notifNewProjectTitle = TranslatableString(
    en: 'New project — needs acceptance',
    ar: 'مشروع جديد — بحاجة للقبول',
    ur: 'نیا پروجیکٹ — قبولیت درکار',
    hi: 'नई परियोजना — स्वीकृति आवश्यक',
  );
  static const notifProjectAcceptedTitle = TranslatableString(
    en: 'Procurement accepted your project',
    ar: 'قبلت المشتريات مشروعك',
    ur: 'پروکیورمنٹ نے آپ کا پروجیکٹ قبول کر لیا',
    hi: 'खरीद ने आपकी परियोजना स्वीकार की',
  );
  static const notifPlanMarkedDoneTitle = TranslatableString(
    en: 'Procurement marked your plan as Done',
    ar: 'أنهت المشتريات خطتك',
    ur: 'پروکیورمنٹ نے آپ کا پلان مکمل کر دیا',
    hi: 'खरीद ने आपकी योजना पूर्ण के रूप में चिह्नित की',
  );
  static const notifRequestDispatchedTitle = TranslatableString(
    en: 'Request dispatched to site',
    ar: 'تم إرسال الطلب إلى الموقع',
    ur: 'درخواست سائٹ پر روانہ کر دی گئی',
    hi: 'अनुरोध साइट पर भेजा गया',
  );
  static const notifPlanApprovedTitle = TranslatableString(
    en: 'Engineer approved the plan',
    ar: 'وافق المهندس على الخطة',
    ur: 'انجینئر نے پلان منظور کر لیا',
    hi: 'इंजीनियर ने योजना स्वीकृत की',
  );
  static const notifPlanChangesTitle = TranslatableString(
    en: 'Engineer requested plan changes',
    ar: 'طلب المهندس تعديلات على الخطة',
    ur: 'انجینئر نے پلان میں تبدیلیاں مانگی ہیں',
    hi: 'इंजीनियर ने योजना में बदलाव मांगे',
  );
  static const notifPlanCommentTitle = TranslatableString(
    en: 'Procurement commented on your plan',
    ar: 'علّقت المشتريات على خطتك',
    ur: 'پروکیورمنٹ نے آپ کے پلان پر تبصرہ کیا',
    hi: 'खरीद ने आपकी योजना पर टिप्पणी की',
  );
  static const notifRequestHeldTitle = TranslatableString(
    en: 'Procurement put your request on hold',
    ar: 'علّقت المشتريات طلبك',
    ur: 'پروکیورمنٹ نے آپ کی درخواست روک دی',
    hi: 'खरीद ने आपका अनुरोध रोक दिया',
  );
  static const notifNewRequestComment = TranslatableString(
    en: 'New comment on a request',
    ar: 'تعليق جديد على طلب',
    ur: 'درخواست پر نیا تبصرہ',
    hi: 'अनुरोध पर नई टिप्पणी',
  );
  static const requestEdited = TranslatableString(
    en: 'Request updated',
    ar: 'تم تحديث الطلب',
    ur: 'درخواست اپ ڈیٹ ہو گئی',
    hi: 'अनुरोध अपडेट किया गया',
  );
  static const notifRequestEditedTitle = TranslatableString(
    en: 'Engineer edited a request',
    ar: 'عدّل المهندس طلبًا',
    ur: 'انجینئر نے درخواست میں ترمیم کی',
    hi: 'इंजीनियर ने अनुरोध संपादित किया',
  );
  static const editRequest = TranslatableString(
    en: 'Edit request',
    ar: 'تعديل الطلب',
    ur: 'درخواست میں ترمیم کریں',
    hi: 'अनुरोध संपादित करें',
  );
  static const editRequestConfirmTitle = TranslatableString(
    en: 'Apply these changes?',
    ar: 'تطبيق هذه التغييرات؟',
    ur: 'یہ تبدیلیاں لاگو کریں؟',
    hi: 'ये बदलाव लागू करें?',
  );
  static const editRequestDropBody = TranslatableString(
    en: 'item(s) will be dropped from this request and procurement notified. This can\'t be undone.',
    ar: 'سيتم حذف بند(بنود) من هذا الطلب وإخطار المشتريات. لا يمكن التراجع.',
    ur: 'اس درخواست سے آئٹم حذف ہو جائیں گے اور پروکیورمنٹ کو مطلع کیا جائے گا۔ یہ واپس نہیں ہو سکتا۔',
    hi: 'इस अनुरोध से आइटम हटाए जाएँगे और खरीद को सूचित किया जाएगा। यह पूर्ववत नहीं हो सकता।',
  );
  static const notifIdleRequestTitle = TranslatableString(
    en: 'Request idle for 24h+',
    ar: 'طلب بدون إجراء لأكثر من ٢٤ ساعة',
    ur: '24 گھنٹے سے غیر فعال درخواست',
    hi: 'अनुरोध 24 घंटे+ से निष्क्रिय',
  );
  static const plansToReview = TranslatableString(
    en: 'Plans to review',
    ar: 'خطط للمراجعة',
    ur: 'جائزے کے لیے پلان',
    hi: 'समीक्षा हेतु योजनाएं',
  );
  static const requestsToDispatch = TranslatableString(
    en: 'Requests to dispatch',
    ar: 'طلبات للصرف',
    ur: 'روانگی کے لیے درخواستیں',
    hi: 'भेजने हेतु अनुरोध',
  );
  static const noPlansToReview = TranslatableString(
    en: 'No plans waiting',
    ar: 'لا توجد خطط منتظرة',
    ur: 'کوئی پلان زیر التوا نہیں',
    hi: 'कोई योजना लंबित नहीं',
  );
  static const noRequestsToDispatch = TranslatableString(
    en: 'No requests waiting',
    ar: 'لا توجد طلبات منتظرة',
    ur: 'کوئی درخواست زیر التوا نہیں',
    hi: 'कोई अनुरोध लंबित नहीं',
  );
  static const newProjectsQueue = TranslatableString(
    en: 'New projects',
    ar: 'مشاريع جديدة',
    ur: 'نئے پروجیکٹس',
    hi: 'नई परियोजनाएं',
  );
  static const noNewProjects = TranslatableString(
    en: 'No new projects',
    ar: 'لا مشاريع جديدة',
    ur: 'کوئی نیا پروجیکٹ نہیں',
    hi: 'कोई नई परियोजना नहीं',
  );
  static const reviewPlan = TranslatableString(
    en: 'Review Plan',
    ar: 'مراجعة الخطة',
    ur: 'پلان کا جائزہ',
    hi: 'योजना समीक्षा',
  );
  static const markArranged = TranslatableString(
    en: 'Mark arranged',
    ar: 'وضع علامة مرتب',
    ur: 'بندوبست نشان زد',
    hi: 'व्यवस्थित चिह्नित',
  );
  static const arranged = TranslatableString(
    en: 'Arranged',
    ar: 'تم الترتيب',
    ur: 'بندوبست شدہ',
    hi: 'व्यवस्थित',
  );
  static const markAllArranged = TranslatableString(
    en: 'Arrange all',
    ar: 'ترتيب الكل',
    ur: 'سب کا بندوبست',
    hi: 'सभी व्यवस्थित',
  );
  static const markDone = TranslatableString(
    en: 'Mark Done',
    ar: 'وضع علامة تم',
    ur: 'مکمل نشان زد',
    hi: 'पूर्ण चिह्नित',
  );
  static const planMarkedDone = TranslatableString(
    en: 'Plan sent back for approval',
    ar: 'تم إرسال الخطة للموافقة',
    ur: 'پلان منظوری کے لیے واپس بھیجا',
    hi: 'योजना अनुमोदन हेतु भेजी',
  );
  static const arrangeAllFirst = TranslatableString(
    en: 'Arrange every item to finish',
    ar: 'رتّب كل عنصر للإنهاء',
    ur: 'مکمل کرنے کے لیے ہر آئٹم کا بندوبست کریں',
    hi: 'समाप्त करने हेतु हर आइटम व्यवस्थित करें',
  );
  static const dispatch = TranslatableString(
    en: 'Dispatch',
    ar: 'صرف',
    ur: 'روانہ کریں',
    hi: 'भेजें',
  );
  static const dispatchRequest = TranslatableString(
    en: 'Dispatch Request',
    ar: 'صرف الطلب',
    ur: 'درخواست روانہ کریں',
    hi: 'अनुरोध भेजें',
  );
  static const requestDispatched = TranslatableString(
    en: 'Request dispatched',
    ar: 'تم صرف الطلب',
    ur: 'درخواست روانہ ہو گئی',
    hi: 'अनुरोध भेजा गया',
  );
  static const notInInventory = TranslatableString(
    en: 'Not in inventory',
    ar: 'غير موجود في المخزون',
    ur: 'انوینٹری میں نہیں',
    hi: 'इन्वेंटरी में नहीं',
  );
  static const receiveIntoInventory = TranslatableString(
    en: 'Receive into inventory',
    ar: 'استلام في المخزون',
    ur: 'انوینٹری میں وصول کریں',
    hi: 'इन्वेंटरी में प्राप्त करें',
  );
  static const quantityToStock = TranslatableString(
    en: 'Quantity to stock',
    ar: 'الكمية المراد تخزينها',
    ur: 'اسٹاک کرنے کی مقدار',
    hi: 'स्टॉक करने की मात्रा',
  );
  static const readyToDispatch = TranslatableString(
    en: 'Ready to dispatch',
    ar: 'جاهز للصرف',
    ur: 'روانگی کے لیے تیار',
    hi: 'भेजने के लिए तैयार',
  );
  static const needsStocking = TranslatableString(
    en: 'Needs stocking',
    ar: 'بحاجة إلى تخزين',
    ur: 'اسٹاک کی ضرورت',
    hi: 'स्टॉक की आवश्यकता',
  );
  static const confirmDispatchTitle = TranslatableString(
    en: 'Dispatch now?',
    ar: 'الصرف الآن؟',
    ur: 'ابھی روانہ کریں؟',
    hi: 'अभी भेजें?',
  );
  static const lineItems = TranslatableString(
    en: 'Line items',
    ar: 'البنود',
    ur: 'آئٹمز',
    hi: 'मद',
  );
  static const unitCost = TranslatableString(
    en: 'Unit cost',
    ar: 'تكلفة الوحدة',
    ur: 'فی یونٹ لاگت',
    hi: 'इकाई लागत',
  );
  static const putOnHold = TranslatableString(
    en: 'On hold',
    ar: 'قيد الانتظار',
    ur: 'روک دیں',
    hi: 'रोकें',
  );
  static const holdNote = TranslatableString(
    en: 'Reason / note',
    ar: 'السبب / ملاحظة',
    ur: 'وجہ / نوٹ',
    hi: 'कारण / नोट',
  );
  static const enterDispatchQty = TranslatableString(
    en: 'Enter a quantity to dispatch',
    ar: 'أدخل كمية للصرف',
    ur: 'روانگی کے لیے مقدار درج کریں',
    hi: 'भेजने हेतु मात्रा दर्ज करें',
  );
  static const requested = TranslatableString(
    en: 'Requested',
    ar: 'مطلوب',
    ur: 'درخواست شدہ',
    hi: 'अनुरोधित',
  );

  // ─── Admin panel — user management (§4.7) ─────────────────────
  static const userManagement = TranslatableString(
    en: 'User Management',
    ar: 'إدارة المستخدمين',
    ur: 'صارف مینجمنٹ',
    hi: 'उपयोगकर्ता प्रबंधन',
  );
  static const addUser = TranslatableString(
    en: 'Add user',
    ar: 'إضافة مستخدم',
    ur: 'صارف شامل کریں',
    hi: 'उपयोगकर्ता जोड़ें',
  );
  static const createUser = TranslatableString(
    en: 'Create user',
    ar: 'إنشاء مستخدم',
    ur: 'صارف بنائیں',
    hi: 'उपयोगकर्ता बनाएं',
  );
  static const projectEngineerRole = TranslatableString(
    en: 'Project Engineer',
    ar: 'مهندس المشروع',
    ur: 'پراجیکٹ انجینئر',
    hi: 'परियोजना इंजीनियर',
  );
  static const siteEngineerRole = TranslatableString(
    en: 'Site Engineer',
    ar: 'مهندس الموقع',
    ur: 'سائٹ انجینئر',
    hi: 'साइट इंजीनियर',
  );
  static const seniorMechanicalEngineerRole = TranslatableString(
    en: 'Senior Mechanical Engineer',
    ar: 'مهندس ميكانيكي أول',
    ur: 'سینئر مکینیکل انجینئر',
    hi: 'वरिष्ठ मैकेनिकल इंजीनियर',
  );
  static const projectManagerRole = TranslatableString(
    en: 'Project Manager',
    ar: 'مدير المشروع',
    ur: 'پروجیکٹ مینیجر',
    hi: 'परियोजना प्रबंधक',
  );
  static const workshopInChargeRole = TranslatableString(
    en: 'Workshop In-Charge',
    ar: 'مسؤول الورشة',
    ur: 'ورکشاپ انچارج',
    hi: 'कार्यशाला प्रभारी',
  );
  static const documentControllerRole = TranslatableString(
    en: 'Document Controller',
    ar: 'مراقب المستندات',
    ur: 'دستاویز کنٹرولر',
    hi: 'दस्तावेज़ नियंत्रक',
  );
  static const accountantRole = TranslatableString(
    en: 'Accountant',
    ar: 'محاسب',
    ur: 'اکاؤنٹنٹ',
    hi: 'लेखाकार',
  );
  static const procurementRole = TranslatableString(
    en: 'Procurement',
    ar: 'المشتريات',
    ur: 'پروکیورمنٹ',
    hi: 'खरीद',
  );
  static const adminRole = TranslatableString(
    en: 'Admin',
    ar: 'المسؤول',
    ur: 'ایڈمن',
    hi: 'एडमिन',
  );
  static const yorksV1RoleMappingRequired = TranslatableString(
    en: 'Role mapping required',
    ar: 'تعيين الدور مطلوب',
    ur: 'کردار کی تعیین ضروری ہے',
    hi: 'भूमिका मैपिंग आवश्यक है',
  );
  static const userActive = TranslatableString(
    en: 'Active',
    ar: 'نشط',
    ur: 'فعال',
    hi: 'सक्रिय',
  );
  static const userInactive = TranslatableString(
    en: 'Inactive',
    ar: 'غير نشط',
    ur: 'غیر فعال',
    hi: 'निष्क्रिय',
  );
  static const fullName = TranslatableString(
    en: 'Full name',
    ar: 'الاسم الكامل',
    ur: 'پورا نام',
    hi: 'पूरा नाम',
  );
  static const initialPassword = TranslatableString(
    en: 'Initial password',
    ar: 'كلمة المرور الأولية',
    ur: 'ابتدائی پاس ورڈ',
    hi: 'प्रारंभिक पासवर्ड',
  );
  static const passwordTooShort = TranslatableString(
    en: 'At least 6 characters',
    ar: '6 أحرف على الأقل',
    ur: 'کم از کم 6 حروف',
    hi: 'कम से कम 6 अक्षर',
  );
  static const setNewPassword = TranslatableString(
    en: 'Set a new password',
    ar: 'عيّن كلمة مرور جديدة',
    ur: 'نیا پاس ورڈ مقرر کریں',
    hi: 'नया पासवर्ड सेट करें',
  );
  static const setNewPasswordBody = TranslatableString(
    en: 'Choose a password only you know before continuing.',
    ar: 'اختر كلمة مرور تعرفها أنت وحدك قبل المتابعة.',
    ur: 'جاری رکھنے سے پہلے صرف اپنا معلوم پاس ورڈ منتخب کریں۔',
    hi: 'जारी रखने से पहले केवल आपको ज्ञात पासवर्ड चुनें।',
  );
  static const newPasswordLabel = TranslatableString(
    en: 'New password',
    ar: 'كلمة المرور الجديدة',
    ur: 'نیا پاس ورڈ',
    hi: 'नया पासवर्ड',
  );
  static const confirmPasswordLabel = TranslatableString(
    en: 'Confirm password',
    ar: 'تأكيد كلمة المرور',
    ur: 'پاس ورڈ کی تصدیق',
    hi: 'पासवर्ड की पुष्टि',
  );
  static const passwordsDoNotMatch = TranslatableString(
    en: 'Passwords do not match',
    ar: 'كلمتا المرور غير متطابقتين',
    ur: 'پاس ورڈ مطابقت نہیں رکھتے',
    hi: 'पासवर्ड मेल नहीं खाते',
  );
  static const saveAndContinue = TranslatableString(
    en: 'Save & continue',
    ar: 'حفظ ومتابعة',
    ur: 'محفوظ کریں اور جاری رکھیں',
    hi: 'सहेजें और जारी रखें',
  );
  static const passwordChangeFailed = TranslatableString(
    en: 'Couldn\'t change the password. Check your connection and try again.',
    ar: 'تعذّر تغيير كلمة المرور. تحقق من اتصالك وحاول مرة أخرى.',
    ur: 'پاس ورڈ تبدیل نہ ہو سکا۔ کنکشن چیک کر کے دوبارہ کوشش کریں۔',
    hi: 'पासवर्ड नहीं बदल सका। कनेक्शन जांचें और पुनः प्रयास करें।',
  );
  static const accountActive = TranslatableString(
    en: 'Account active',
    ar: 'الحساب نشط',
    ur: 'اکاؤنٹ فعال',
    hi: 'खाता सक्रिय',
  );
  static const accountActiveHint = TranslatableString(
    en: 'Turn off to deny access immediately',
    ar: 'أوقفه لمنع الوصول فورًا',
    ur: 'رسائی فوراً روکنے کے لیے بند کریں',
    hi: 'पहुँच तुरंत रोकने हेतु बंद करें',
  );
  static const inventoryAccess = TranslatableString(
    en: 'Inventory access',
    ar: 'الوصول للمخزون',
    ur: 'انوینٹری رسائی',
    hi: 'इन्वेंट्री पहुँच',
  );
  static const inventoryAccessHint = TranslatableString(
    en: 'Allow this engineer to browse stock',
    ar: 'السماح لهذا المهندس بتصفح المخزون',
    ur: 'اس انجینئر کو اسٹاک دیکھنے کی اجازت',
    hi: 'इस इंजीनियर को स्टॉक देखने दें',
  );
  static const resetPassword = TranslatableString(
    en: 'Reset password',
    ar: 'إعادة تعيين كلمة المرور',
    ur: 'پاس ورڈ ری سیٹ',
    hi: 'पासवर्ड रीसेट',
  );
  static const passwordResetSent = TranslatableString(
    en: 'Password reset link sent',
    ar: 'تم إرسال رابط إعادة التعيين',
    ur: 'پاس ورڈ ری سیٹ لنک بھیج دیا',
    hi: 'पासवर्ड रीसेट लिंक भेजा',
  );
  static const exportAudit = TranslatableString(
    en: 'Export CSV',
    ar: 'تصدير CSV',
    ur: 'CSV ایکسپورٹ',
    hi: 'CSV निर्यात',
  );
  static const searchAudit = TranslatableString(
    en: 'Search by user, action or detail',
    ar: 'البحث بالمستخدم أو الإجراء',
    ur: 'صارف، عمل یا تفصیل سے تلاش',
    hi: 'उपयोगकर्ता, क्रिया से खोजें',
  );
  static const auditCopied = TranslatableString(
    en: 'Audit trail copied to clipboard',
    ar: 'تم نسخ سجل التدقيق',
    ur: 'آڈٹ ٹریل کلپ بورڈ پر کاپی',
    hi: 'ऑडिट ट्रेल क्लिपबोर्ड पर कॉपी',
  );

  // ─── Admin panel hub (§4.7) ───────────────────────────────────
  static const adminPanel = TranslatableString(
    en: 'Admin Panel',
    ar: 'لوحة الإدارة',
    ur: 'ایڈمن پینل',
    hi: 'एडमिन पैनल',
  );
  static const adminPanelHint = TranslatableString(
    en: 'Users, projects, oversight & reports',
    ar: 'المستخدمون والمشاريع والإشراف والتقارير',
    ur: 'صارفین، پروجیکٹس، نگرانی اور رپورٹس',
    hi: 'उपयोगकर्ता, परियोजनाएं, निगरानी और रिपोर्ट',
  );
  static const overview = TranslatableString(
    en: 'Overview',
    ar: 'نظرة عامة',
    ur: 'جائزہ',
    hi: 'अवलोकन',
  );
  static const management = TranslatableString(
    en: 'Management',
    ar: 'الإدارة',
    ur: 'انتظام',
    hi: 'प्रबंधन',
  );
  static const oversight = TranslatableString(
    en: 'Oversight',
    ar: 'الإشراف',
    ur: 'نگرانی',
    hi: 'निगरानी',
  );
  static const activeUsers = TranslatableString(
    en: 'Active users',
    ar: 'المستخدمون النشطون',
    ur: 'فعال صارفین',
    hi: 'सक्रिय उपयोगकर्ता',
  );
  static const auditTrail = TranslatableString(
    en: 'Audit Trail',
    ar: 'سجل التدقيق',
    ur: 'آڈٹ ٹریل',
    hi: 'ऑडिट ट्रेल',
  );
  static const projectsAdmin = TranslatableString(
    en: 'Projects',
    ar: 'المشاريع',
    ur: 'پروجیکٹس',
    hi: 'परियोजनाएं',
  );
  static const requestsAdmin = TranslatableString(
    en: 'Requests',
    ar: 'الطلبات',
    ur: 'درخواستیں',
    hi: 'अनुरोध',
  );
  static const userManagementHint = TranslatableString(
    en: 'Create, deactivate & set access',
    ar: 'إنشاء وتعطيل وضبط الوصول',
    ur: 'بنائیں، غیر فعال کریں اور رسائی',
    hi: 'बनाएं, निष्क्रिय करें और पहुँच',
  );
  static const projectsAdminHint = TranslatableString(
    en: 'View & delete any project',
    ar: 'عرض وحذف أي مشروع',
    ur: 'کوئی بھی پروجیکٹ دیکھیں اور حذف کریں',
    hi: 'कोई भी परियोजना देखें और हटाएं',
  );
  static const requestsAdminHint = TranslatableString(
    en: 'Reject or delete any request',
    ar: 'رفض أو حذف أي طلب',
    ur: 'کوئی بھی درخواست مسترد یا حذف کریں',
    hi: 'कोई भी अनुरोध अस्वीकार या हटाएं',
  );
  static const procurementHint = TranslatableString(
    en: 'Plans to review & requests to dispatch',
    ar: 'خطط للمراجعة وطلبات للصرف',
    ur: 'جائزے کے پلان اور روانگی کی درخواستیں',
    hi: 'समीक्षा योजनाएं और भेजने हेतु अनुरोध',
  );
  static const inventoryHint = TranslatableString(
    en: 'Add, edit & adjust stock',
    ar: 'إضافة وتعديل وضبط المخزون',
    ur: 'اسٹاک شامل، ترمیم اور ایڈجسٹ',
    hi: 'स्टॉक जोड़ें, संपादित करें',
  );
  static const costReportHint = TranslatableString(
    en: 'Material value dispatched per project',
    ar: 'قيمة المواد المصروفة لكل مشروع',
    ur: 'فی پروجیکٹ روانہ مواد کی قیمت',
    hi: 'प्रति परियोजना भेजी सामग्री मूल्य',
  );
  static const auditTrailHint = TranslatableString(
    en: 'Every action, filter & export',
    ar: 'كل إجراء، تصفية وتصدير',
    ur: 'ہر عمل، فلٹر اور ایکسپورٹ',
    hi: 'हर क्रिया, फ़िल्टर और निर्यात',
  );
  static const peopleHint = TranslatableString(
    en: 'Employees, attendance & leave',
    ar: 'الموظفون والحضور والإجازات',
    ur: 'ملازمین، حاضری اور چھٹی',
    hi: 'कर्मचारी, उपस्थिति और अवकाश',
  );
  static const rentalsHint = TranslatableString(
    en: 'Units, tenants & rent collection',
    ar: 'الوحدات والمستأجرون وتحصيل الإيجار',
    ur: 'یونٹس، کرایہ دار اور کرایہ وصولی',
    hi: 'इकाइयाँ, किरायेदार और किराया',
  );
  static const deleteProject = TranslatableString(
    en: 'Delete project',
    ar: 'حذف المشروع',
    ur: 'پروجیکٹ حذف کریں',
    hi: 'परियोजना हटाएं',
  );
  static const projectDeleted = TranslatableString(
    en: 'Project deleted',
    ar: 'تم حذف المشروع',
    ur: 'پروجیکٹ حذف ہو گیا',
    hi: 'परियोजना हटा दी',
  );
  static const rejectRequest = TranslatableString(
    en: 'Reject',
    ar: 'رفض',
    ur: 'مسترد کریں',
    hi: 'अस्वीकार',
  );
  static const deleteRequest = TranslatableString(
    en: 'Delete request',
    ar: 'حذف الطلب',
    ur: 'درخواست حذف کریں',
    hi: 'अनुरोध हटाएं',
  );
  static const requestDeleted = TranslatableString(
    en: 'Request deleted',
    ar: 'تم حذف الطلب',
    ur: 'درخواست حذف ہو گئی',
    hi: 'अनुरोध हटाया गया',
  );

  // ─── Goods receipt (procurement) ──────────────────────────────
  static const receiveGoods = TranslatableString(
    en: 'Receive Goods',
    ar: 'استلام البضائع',
    ur: 'سامان وصول کریں',
    hi: 'माल प्राप्त करें',
  );
  static const goodsReceipt = TranslatableString(
    en: 'Goods Receipt',
    ar: 'إيصال استلام',
    ur: 'گڈز رسید',
    hi: 'माल रसीद',
  );
  static const grnSelectMaterial = TranslatableString(
    en: 'Select a material',
    ar: 'اختر مادة',
    ur: 'مواد منتخب کریں',
    hi: 'सामग्री चुनें',
  );
  static const grnTapToChoose = TranslatableString(
    en: 'Tap to choose from inventory',
    ar: 'اضغط للاختيار من المخزون',
    ur: 'انوینٹری سے منتخب کرنے کے لیے ٹیپ کریں',
    hi: 'इन्वेंट्री से चुनने के लिए टैप करें',
  );
  static const grnRecord = TranslatableString(
    en: 'Record receipt',
    ar: 'تسجيل الاستلام',
    ur: 'رسید درج کریں',
    hi: 'रसीद दर्ज करें',
  );
  static const grnRecorded = TranslatableString(
    en: 'Goods received into store',
    ar: 'تم استلام البضائع في المخزن',
    ur: 'سامان اسٹور میں وصول ہوا',
    hi: 'माल स्टोर में प्राप्त हुआ',
  );
  static const onHand = TranslatableString(
    en: 'On hand',
    ar: 'المتوفر',
    ur: 'موجود',
    hi: 'उपलब्ध',
  );
  static const supplier = TranslatableString(
    en: 'Supplier',
    ar: 'المورّد',
    ur: 'سپلائر',
    hi: 'आपूर्तिकर्ता',
  );

  // ─── Finance / cost roll-up (admin) ───────────────────────────
  static const finance = TranslatableString(
    en: 'Finance',
    ar: 'المالية',
    ur: 'فنانس',
    hi: 'वित्त',
  );
  static const projectCosts = TranslatableString(
    en: 'Project Costs',
    ar: 'تكاليف المشاريع',
    ur: 'پروجیکٹ اخراجات',
    hi: 'परियोजना लागत',
  );
  static const dispatched = TranslatableString(
    en: 'Dispatched',
    ar: 'تم الصرف',
    ur: 'روانہ',
    hi: 'भेजा गया',
  );
  static const returnedLabel = TranslatableString(
    en: 'Returned',
    ar: 'مُرجع',
    ur: 'واپس',
    hi: 'वापस',
  );
  static const netCost = TranslatableString(
    en: 'Net cost',
    ar: 'التكلفة الصافية',
    ur: 'خالص لاگت',
    hi: 'शुद्ध लागत',
  );
  static const totalNetCost = TranslatableString(
    en: 'Total net cost',
    ar: 'إجمالي التكلفة الصافية',
    ur: 'کل خالص لاگت',
    hi: 'कुल शुद्ध लागत',
  );
  static const exportCsv = TranslatableString(
    en: 'Export CSV',
    ar: 'تصدير CSV',
    ur: 'CSV ایکسپورٹ',
    hi: 'CSV निर्यात',
  );
  static const csvCopied = TranslatableString(
    en: 'CSV copied to clipboard',
    ar: 'تم نسخ CSV إلى الحافظة',
    ur: 'CSV کلپ بورڈ پر کاپی ہو گیا',
    hi: 'CSV क्लिपबोर्ड पर कॉपी हुआ',
  );
  static const markComplete = TranslatableString(
    en: 'Mark complete',
    ar: 'وضع علامة مكتمل',
    ur: 'مکمل نشان زد کریں',
    hi: 'पूर्ण चिह्नित करें',
  );
  static const cannotCompleteOpenRequests = TranslatableString(
    en: 'Close all open requests first',
    ar: 'أغلق جميع الطلبات المفتوحة أولاً',
    ur: 'پہلے تمام کھلی درخواستیں بند کریں',
    hi: 'पहले सभी खुले अनुरोध बंद करें',
  );
  static const projectCompleted = TranslatableString(
    en: 'Project closed out',
    ar: 'تم إغلاق المشروع',
    ur: 'پروجیکٹ مکمل ہو گیا',
    hi: 'परियोजना पूर्ण हुई',
  );

  // ─── Rentals module ───────────────────────────────────────────
  static const rentals = TranslatableString(
    en: 'Rentals',
    ar: 'الإيجارات',
    ur: 'کرایہ جات',
    hi: 'किराया',
  );
  static const rentalShops = TranslatableString(
    en: 'Rental Shops',
    ar: 'المحلات المؤجرة',
    ur: 'کرایہ کی دکانیں',
    hi: 'किराये की दुकानें',
  );
  static const rentalUnits = TranslatableString(
    en: 'Units',
    ar: 'الوحدات',
    ur: 'یونٹس',
    hi: 'इकाइयाँ',
  );
  static const addUnit = TranslatableString(
    en: 'Add Unit',
    ar: 'إضافة وحدة',
    ur: 'یونٹ شامل کریں',
    hi: 'इकाई जोड़ें',
  );
  static const unitName = TranslatableString(
    en: 'Unit name',
    ar: 'اسم الوحدة',
    ur: 'یونٹ کا نام',
    hi: 'इकाई नाम',
  );
  static const unitType = TranslatableString(
    en: 'Type',
    ar: 'النوع',
    ur: 'قسم',
    hi: 'प्रकार',
  );
  static const location = TranslatableString(
    en: 'Location',
    ar: 'الموقع',
    ur: 'مقام',
    hi: 'स्थान',
  );
  static const monthlyRent = TranslatableString(
    en: 'Monthly rent',
    ar: 'الإيجار الشهري',
    ur: 'ماہانہ کرایہ',
    hi: 'मासिक किराया',
  );
  static const tenant = TranslatableString(
    en: 'Tenant',
    ar: 'المستأجر',
    ur: 'کرایہ دار',
    hi: 'किरायेदार',
  );
  static const tenantContact = TranslatableString(
    en: 'Tenant contact',
    ar: 'هاتف المستأجر',
    ur: 'کرایہ دار رابطہ',
    hi: 'किरायेदार संपर्क',
  );
  static const leaseStart = TranslatableString(
    en: 'Lease start',
    ar: 'بداية العقد',
    ur: 'لیز کا آغاز',
    hi: 'पट्टा प्रारंभ',
  );
  static const leaseEnd = TranslatableString(
    en: 'Lease end',
    ar: 'نهاية العقد',
    ur: 'لیز کا اختتام',
    hi: 'पट्टा समाप्ति',
  );
  static const editUnit = TranslatableString(
    en: 'Edit unit',
    ar: 'تعديل الوحدة',
    ur: 'یونٹ میں ترمیم',
    hi: 'इकाई संपादित करें',
  );
  static const occupancy = TranslatableString(
    en: 'Occupancy',
    ar: 'الإشغال',
    ur: 'قبضہ',
    hi: 'अधिभोग',
  );
  static const leaseExpired = TranslatableString(
    en: 'Lease expired',
    ar: 'انتهى العقد',
    ur: 'لیز ختم',
    hi: 'पट्टा समाप्त',
  );
  static const voidPaymentAction = TranslatableString(
    en: 'Void payment',
    ar: 'إلغاء الدفعة',
    ur: 'ادائیگی منسوخ کریں',
    hi: 'भुगतान रद्द करें',
  );
  static const voided = TranslatableString(
    en: 'Voided',
    ar: 'ملغاة',
    ur: 'منسوخ',
    hi: 'रद्द',
  );
  static const voidReasonLabel = TranslatableString(
    en: 'Reason (optional)',
    ar: 'السبب (اختياري)',
    ur: 'وجہ (اختیاری)',
    hi: 'कारण (वैकल्पिक)',
  );
  static const cashReceived = TranslatableString(
    en: 'Cash received',
    ar: 'النقد المستلم',
    ur: 'موصول رقم',
    hi: 'प्राप्त नकद',
  );
  static const goBack = TranslatableString(
    en: 'Go back',
    ar: 'رجوع',
    ur: 'واپس',
    hi: 'वापस',
  );
  static const setDate = TranslatableString(
    en: 'Set date',
    ar: 'تحديد التاريخ',
    ur: 'تاریخ مقرر کریں',
    hi: 'तारीख़ चुनें',
  );
  static const overpaymentTitle = TranslatableString(
    en: 'Amount exceeds outstanding',
    ar: 'المبلغ يتجاوز المستحق',
    ur: 'رقم واجب الادا سے زیادہ ہے',
    hi: 'राशि बकाया से अधिक है',
  );
  static const overpaymentBody = TranslatableString(
    en: 'This payment is over the outstanding balance by',
    ar: 'تتجاوز هذه الدفعة الرصيد المستحق بمقدار',
    ur: 'یہ ادائیگی واجب الادا رقم سے زیادہ ہے بمقدار',
    hi: 'यह भुगतान बकाया से अधिक है',
  );
  static const recordAnyway = TranslatableString(
    en: 'Record anyway',
    ar: 'سجّل على أي حال',
    ur: 'پھر بھی ریکارڈ کریں',
    hi: 'फिर भी दर्ज करें',
  );
  static const monthNotFuture = TranslatableString(
    en: 'Not in the future',
    ar: 'ليس في المستقبل',
    ur: 'مستقبل میں نہیں',
    hi: 'भविष्य में नहीं',
  );
  static const monthTooOld = TranslatableString(
    en: 'Too far back',
    ar: 'قديم جدًا',
    ur: 'بہت پرانا',
    hi: 'बहुत पुराना',
  );
  static const recordPayment = TranslatableString(
    en: 'Record payment',
    ar: 'تسجيل دفعة',
    ur: 'ادائیگی درج کریں',
    hi: 'भुगतान दर्ज करें',
  );
  static const paymentRecorded = TranslatableString(
    en: 'Payment recorded',
    ar: 'تم تسجيل الدفعة',
    ur: 'ادائیگی درج ہو گئی',
    hi: 'भुगतान दर्ज हुआ',
  );
  static const amountPaid = TranslatableString(
    en: 'Amount paid',
    ar: 'المبلغ المدفوع',
    ur: 'ادا کی گئی رقم',
    hi: 'भुगतान राशि',
  );
  static const amountDue = TranslatableString(
    en: 'Amount due',
    ar: 'المبلغ المستحق',
    ur: 'واجب رقم',
    hi: 'देय राशि',
  );
  static const paymentMethod = TranslatableString(
    en: 'Method',
    ar: 'الطريقة',
    ur: 'طریقہ',
    hi: 'विधि',
  );
  static const rentRoll = TranslatableString(
    en: 'Monthly rent roll',
    ar: 'إجمالي الإيجار الشهري',
    ur: 'ماہانہ کرایہ کل',
    hi: 'मासिक किराया योग',
  );
  static const collectedThisMonth = TranslatableString(
    en: 'Collected this month',
    ar: 'المحصّل هذا الشهر',
    ur: 'اس ماہ وصول',
    hi: 'इस माह वसूल',
  );
  static const overdueTotal = TranslatableString(
    en: 'Overdue',
    ar: 'متأخر',
    ur: 'واجب الادا',
    hi: 'अतिदेय',
  );
  static const paymentHistory = TranslatableString(
    en: 'Payment history',
    ar: 'سجل الدفعات',
    ur: 'ادائیگی کی تاریخ',
    hi: 'भुगतान इतिहास',
  );
  static const noPaymentsYet = TranslatableString(
    en: 'No payments yet',
    ar: 'لا توجد دفعات بعد',
    ur: 'ابھی کوئی ادائیگی نہیں',
    hi: 'अभी कोई भुगतान नहीं',
  );
  static const noUnitsYet = TranslatableString(
    en: 'No units yet',
    ar: 'لا توجد وحدات بعد',
    ur: 'ابھی کوئی یونٹ نہیں',
    hi: 'अभी कोई इकाई नहीं',
  );
  static const occupied = TranslatableString(
    en: 'Occupied',
    ar: 'مشغول',
    ur: 'مقبوضہ',
    hi: 'अधिकृत',
  );
  static const vacant = TranslatableString(
    en: 'Vacant',
    ar: 'شاغر',
    ur: 'خالی',
    hi: 'खाली',
  );
  static const saveUnit = TranslatableString(
    en: 'Save unit',
    ar: 'حفظ الوحدة',
    ur: 'یونٹ محفوظ کریں',
    hi: 'इकाई सहेजें',
  );
  static const billingMonth = TranslatableString(
    en: 'Billing month',
    ar: 'شهر الفوترة',
    ur: 'بلنگ مہینہ',
    hi: 'बिलिंग माह',
  );

  // ─── People / HR module ───────────────────────────────────────
  static const people = TranslatableString(
    en: 'People',
    ar: 'الموظفون',
    ur: 'عملہ',
    hi: 'कर्मचारी',
  );
  static const employees = TranslatableString(
    en: 'Employees',
    ar: 'الموظفون',
    ur: 'ملازمین',
    hi: 'कर्मचारी',
  );
  static const presentToday = TranslatableString(
    en: 'Present',
    ar: 'حاضر',
    ur: 'حاضر',
    hi: 'उपस्थित',
  );
  static const onLeaveLabel = TranslatableString(
    en: 'On leave',
    ar: 'في إجازة',
    ur: 'چھٹی پر',
    hi: 'अवकाश पर',
  );
  static const absentLabel = TranslatableString(
    en: 'Absent',
    ar: 'غائب',
    ur: 'غیر حاضر',
    hi: 'अनुपस्थित',
  );
  static const leaveBalanceLabel = TranslatableString(
    en: 'Leave balance',
    ar: 'رصيد الإجازة',
    ur: 'چھٹی بیلنس',
    hi: 'अवकाश शेष',
  );
  static const leaveUsed = TranslatableString(
    en: 'Leave used',
    ar: 'الإجازة المستخدمة',
    ur: 'استعمال شدہ چھٹی',
    hi: 'प्रयुक्त अवकाश',
  );
  static const attendanceLabel = TranslatableString(
    en: 'Attendance',
    ar: 'الحضور',
    ur: 'حاضری',
    hi: 'उपस्थिति',
  );
  static const recordLeave = TranslatableString(
    en: 'Record leave',
    ar: 'تسجيل إجازة',
    ur: 'چھٹی درج کریں',
    hi: 'अवकाश दर्ज करें',
  );
  static const leaveRecorded = TranslatableString(
    en: 'Leave recorded',
    ar: 'تم تسجيل الإجازة',
    ur: 'چھٹی درج ہو گئی',
    hi: 'अवकाश दर्ज हुआ',
  );
  static const markAttendance = TranslatableString(
    en: 'Mark attendance',
    ar: 'تسجيل الحضور',
    ur: 'حاضری لگائیں',
    hi: 'उपस्थिति दर्ज',
  );
  static const salary = TranslatableString(
    en: 'Salary',
    ar: 'الراتب',
    ur: 'تنخواہ',
    hi: 'वेतन',
  );
  static const emiratesId = TranslatableString(
    en: 'Emirates ID',
    ar: 'الهوية الإماراتية',
    ur: 'ایمریٹس آئی ڈی',
    hi: 'अमीरात आईडी',
  );
  static const passportNo = TranslatableString(
    en: 'Passport',
    ar: 'جواز السفر',
    ur: 'پاسپورٹ',
    hi: 'पासपोर्ट',
  );
  static const visaExpiry = TranslatableString(
    en: 'Visa expiry',
    ar: 'انتهاء التأشيرة',
    ur: 'ویزا میعاد',
    hi: 'वीज़ा समाप्ति',
  );
  static const joinDate = TranslatableString(
    en: 'Joined',
    ar: 'تاريخ الالتحاق',
    ur: 'شمولیت',
    hi: 'शामिल',
  );
  static const nationality = TranslatableString(
    en: 'Nationality',
    ar: 'الجنسية',
    ur: 'قومیت',
    hi: 'राष्ट्रीयता',
  );
  static const department = TranslatableString(
    en: 'Department',
    ar: 'القسم',
    ur: 'شعبہ',
    hi: 'विभाग',
  );
  static const documentsLabel = TranslatableString(
    en: 'Documents',
    ar: 'المستندات',
    ur: 'دستاویزات',
    hi: 'दस्तावेज़',
  );
  static const restrictedLabel = TranslatableString(
    en: 'Restricted',
    ar: 'مقيد',
    ur: 'محدود',
    hi: 'प्रतिबंधित',
  );
  static const noEmployeesYet = TranslatableString(
    en: 'No employees yet',
    ar: 'لا يوجد موظفون بعد',
    ur: 'ابھی کوئی ملازم نہیں',
    hi: 'अभी कोई कर्मचारी नहीं',
  );
  static const leaveStart = TranslatableString(
    en: 'From',
    ar: 'من',
    ur: 'سے',
    hi: 'से',
  );
  static const leaveEnd = TranslatableString(
    en: 'To',
    ar: 'إلى',
    ur: 'تک',
    hi: 'तक',
  );
  static const leaveHistory = TranslatableString(
    en: 'Leave history',
    ar: 'سجل الإجازات',
    ur: 'چھٹیوں کی تاریخ',
    hi: 'अवकाश इतिहास',
  );
  static const noLeaveYet = TranslatableString(
    en: 'No leave records',
    ar: 'لا توجد سجلات إجازة',
    ur: 'کوئی چھٹی ریکارڈ نہیں',
    hi: 'कोई अवकाश रिकॉर्ड नहीं',
  );
  static const minStockLevel = TranslatableString(
    en: 'Min. Stock Level',
    ar: 'الحد الأدنى للمخزون',
    ur: 'کم از کم اسٹاک',
    hi: 'न्यूनतम स्टॉक स्तर',
  );
  static const saveMaterial = TranslatableString(
    en: 'Save Material',
    ar: 'حفظ المادة',
    ur: 'مواد محفوظ کریں',
    hi: 'सामग्री सहेजें',
  );
  static const editMaterial = TranslatableString(
    en: 'Edit Material',
    ar: 'تعديل المادة',
    ur: 'مواد ترمیم کریں',
    hi: 'सामग्री संपादित करें',
  );
  static const saveChanges = TranslatableString(
    en: 'Save Changes',
    ar: 'حفظ التغييرات',
    ur: 'تبدیلیاں محفوظ کریں',
    hi: 'परिवर्तन सहेजें',
  );
  static const filterAll = TranslatableString(
    en: 'All',
    ar: 'الكل',
    ur: 'سب',
    hi: 'सभी',
  );
  static const filterIncoming = TranslatableString(
    en: 'Incoming',
    ar: 'الوارد',
    ur: 'آنے والا',
    hi: 'आने वाला',
  );
  static const filterOutgoing = TranslatableString(
    en: 'Outgoing',
    ar: 'الصادر',
    ur: 'جانے والا',
    hi: 'जाने वाला',
  );
  static const filterByType = TranslatableString(
    en: 'Filter by type',
    ar: 'تصفية حسب النوع',
    ur: 'قسم کے مطابق فلٹر',
    hi: 'प्रकार से फ़िल्टर',
  );
  static const searchMaterialsHint = TranslatableString(
    en: 'Search materials...',
    ar: 'البحث في المواد...',
    ur: 'مواد تلاش کریں...',
    hi: 'सामग्री खोजें...',
  );
  static const fieldRequired = TranslatableString(
    en: 'This field is required',
    ar: 'هذا الحقل مطلوب',
    ur: 'یہ فیلڈ ضروری ہے',
    hi: 'यह फ़ील्ड आवश्यक है',
  );
  static const enterValidNumber = TranslatableString(
    en: 'Enter a valid number',
    ar: 'أدخل رقمًا صالحًا',
    ur: 'ایک درست نمبر درج کریں',
    hi: 'एक मान्य संख्या दर्ज करें',
  );
  static const optional = TranslatableString(
    en: 'Optional',
    ar: 'اختياري',
    ur: 'اختیاری',
    hi: 'वैकल्पिक',
  );
  static const materialAdded = TranslatableString(
    en: 'Material added successfully',
    ar: 'تمت إضافة المادة بنجاح',
    ur: 'مواد کامیابی سے شامل کیا گیا',
    hi: 'सामग्री सफलतापूर्वक जोड़ी गई',
  );

  // ─── Record Transaction ─────────────────────────────────────
  static const recordTransaction = TranslatableString(
    en: 'Record Transaction',
    ar: 'تسجيل معاملة',
    ur: 'لین دین ریکارڈ کریں',
    hi: 'लेन-देन दर्ज करें',
  );
  static const incoming = TranslatableString(
    en: 'Incoming',
    ar: 'وارد',
    ur: 'آمد',
    hi: 'आवक',
  );
  static const outgoing = TranslatableString(
    en: 'Outgoing',
    ar: 'صادر',
    ur: 'روانگی',
    hi: 'जावक',
  );
  static const notes = TranslatableString(
    en: 'Notes',
    ar: 'ملاحظات',
    ur: 'نوٹس',
    hi: 'टिप्पणियाँ',
  );
  static const record = TranslatableString(
    en: 'Record',
    ar: 'تسجيل',
    ur: 'ریکارڈ',
    hi: 'दर्ज करें',
  );
  static const transactionRecorded = TranslatableString(
    en: 'Transaction recorded',
    ar: 'تم تسجيل المعاملة',
    ur: 'لین دین ریکارڈ ہوا',
    hi: 'लेन-देन दर्ज किया गया',
  );
  static const insufficientStock = TranslatableString(
    en: 'Insufficient stock',
    ar: 'المخزون غير كافٍ',
    ur: 'اسٹاک ناکافی ہے',
    hi: 'अपर्याप्त स्टॉक',
  );
  static const selectMaterial = TranslatableString(
    en: 'Select Material',
    ar: 'اختر المادة',
    ur: 'مواد منتخب کریں',
    hi: 'सामग्री चुनें',
  );

  // ─── Inventory Detail ───────────────────────────────────────
  static const inStock = TranslatableString(
    en: 'In Stock',
    ar: 'متوفر',
    ur: 'اسٹاک میں',
    hi: 'स्टॉक में',
  );
  static const lowStock = TranslatableString(
    en: 'Low Stock',
    ar: 'مخزون منخفض',
    ur: 'کم اسٹاک',
    hi: 'कम स्टॉक',
  );
  static const outOfStock = TranslatableString(
    en: 'Out of Stock',
    ar: 'نفذ المخزون',
    ur: 'اسٹاک ختم',
    hi: 'स्टॉक समाप्त',
  );
  static const totalValue = TranslatableString(
    en: 'Total Value',
    ar: 'القيمة الإجمالية',
    ur: 'کل قیمت',
    hi: 'कुल मूल्य',
  );
  static const delete = TranslatableString(
    en: 'Delete',
    ar: 'حذف',
    ur: 'حذف کریں',
    hi: 'हटाएं',
  );
  static const confirmDelete = TranslatableString(
    en: 'Are you sure you want to delete this material?',
    ar: 'هل أنت متأكد من حذف هذه المادة؟',
    ur: 'کیا آپ واقعی اس مواد کو حذف کرنا چاہتے ہیں؟',
    hi: 'क्या आप वाकई इस सामग्री को हटाना चाहते हैं?',
  );
  static const cancel = TranslatableString(
    en: 'Cancel',
    ar: 'إلغاء',
    ur: 'منسوخ',
    hi: 'रद्द करें',
  );
  static const today = TranslatableString(
    en: 'Today',
    ar: 'اليوم',
    ur: 'آج',
    hi: 'आज',
  );
  static const yesterday = TranslatableString(
    en: 'Yesterday',
    ar: 'أمس',
    ur: 'کل',
    hi: 'कल',
  );

  // ─── Engineer — Material Requests ────────────────────────────
  static const materialRequests = TranslatableString(
    en: 'Material Requests',
    ar: 'طلبات المواد',
    ur: 'مواد کی درخواستیں',
    hi: 'सामग्री अनुरोध',
  );
  static const allRequests = TranslatableString(
    en: 'All Requests',
    ar: 'جميع الطلبات',
    ur: 'تمام',
    hi: 'सभी अनुरोध',
  );
  static const recentRequests = TranslatableString(
    en: 'Recent',
    ar: 'الأخيرة',
    ur: 'حالیہ',
    hi: 'हालिया',
  );
  static const viewDetails = TranslatableString(
    en: 'VIEW DETAILS',
    ar: 'عرض التفاصيل',
    ur: 'تفصیلات دیکھیں',
    hi: 'विवरण देखें',
  );
  static const pickUp = TranslatableString(
    en: 'PICK UP',
    ar: 'استلام',
    ur: 'وصول کریں',
    hi: 'उठाएं',
  );
  static const historyLabel = TranslatableString(
    en: 'HISTORY',
    ar: 'السجل',
    ur: 'تاریخ',
    hi: 'इतिहास',
  );
  static const dateLabel = TranslatableString(
    en: 'Date',
    ar: 'التاريخ',
    ur: 'تاریخ',
    hi: 'तारीख',
  );
  static const itemCount = TranslatableString(
    en: 'Item Count',
    ar: 'عدد العناصر',
    ur: 'اشیاء کی تعداد',
    hi: 'वस्तु गणना',
  );
  static const items = TranslatableString(
    en: 'Items',
    ar: 'عناصر',
    ur: 'اشیاء',
    hi: 'वस्तुएं',
  );

  // ─── Engineer — Navigation ───────────────────────────────────
  static const requests = TranslatableString(
    en: 'Requests',
    ar: 'الطلبات',
    ur: 'درخواستیں',
    hi: 'अनुरोध',
  );
  static const browse = TranslatableString(
    en: 'Browse',
    ar: 'تصفح',
    ur: 'تلاش',
    hi: 'ब्राउज़',
  );
  static const profile = TranslatableString(
    en: 'My Yorks',
    ar: 'يوركس الخاصة بي',
    ur: 'میرا یورکس',
    hi: 'मेरा यॉर्क्स',
  );
  static const openMyYorks = TranslatableString(
    en: 'Open My Yorks',
    ar: 'افتح يوركس الخاصة بي',
    ur: 'میرا یورکس کھولیں',
    hi: 'मेरा यॉर्क्स खोलें',
  );
  static const verifyingAccount = TranslatableString(
    en: 'Verifying account',
    ar: 'جارٍ التحقق من الحساب',
    ur: 'اکاؤنٹ کی تصدیق ہو رہی ہے',
    hi: 'खाते की पुष्टि हो रही है',
  );
  static const accountUnavailable = TranslatableString(
    en: 'Account details unavailable',
    ar: 'تفاصيل الحساب غير متاحة',
    ur: 'اکاؤنٹ کی تفصیلات دستیاب نہیں',
    hi: 'खाते का विवरण उपलब्ध नहीं है',
  );
  static const workspaceSync = TranslatableString(
    en: 'Workspace sync',
    ar: 'مزامنة مساحة العمل',
    ur: 'ورک اسپیس ہم آہنگی',
    hi: 'वर्कस्पेस सिंक',
  );

  // ─── Engineer — Status Labels ────────────────────────────────
  static const statusPending = TranslatableString(
    en: 'PENDING',
    ar: 'معلق',
    ur: 'زیر التواء',
    hi: 'लंबित',
  );
  static const statusAvailable = TranslatableString(
    en: 'AVAILABLE',
    ar: 'متاح',
    ur: 'دستیاب',
    hi: 'उपलब्ध',
  );
  static const statusDeployed = TranslatableString(
    en: 'DEPLOYED',
    ar: 'تم النشر',
    ur: 'تعینات',
    hi: 'तैनात',
  );
  static const statusRejected = TranslatableString(
    en: 'REJECTED',
    ar: 'مرفوض',
    ur: 'مسترد',
    hi: 'अस्वीकृत',
  );

  // ─── Engineer — Empty / Misc ─────────────────────────────────
  static const noRequestsYet = TranslatableString(
    en: 'No material requests yet',
    ar: 'لا توجد طلبات مواد بعد',
    ur: 'ابھی تک کوئی مواد کی درخواست نہیں',
    hi: 'अभी तक कोई सामग्री अनुरोध नहीं',
  );
  static const tapToCreateRequest = TranslatableString(
    en: 'Tap + to create your first request',
    ar: 'اضغط + لإنشاء أول طلب',
    ur: 'پہلی درخواست بنانے کے لیے + دبائیں',
    hi: 'पहला अनुरोध बनाने के लिए + दबाएं',
  );
  static const browseWarehouse = TranslatableString(
    en: 'Browse Warehouse',
    ar: 'تصفح المستودع',
    ur: 'گودام تلاش کریں',
    hi: 'गोदाम ब्राउज़ करें',
  );
  static const browseDescription = TranslatableString(
    en: 'Explore available materials in the warehouse inventory',
    ar: 'استكشف المواد المتاحة في مخزون المستودع',
    ur: 'گودام کی انوینٹری میں دستیاب مواد دیکھیں',
    hi: 'गोदाम इन्वेंटरी में उपलब्ध सामग्री देखें',
  );
  static const notifications = TranslatableString(
    en: 'Notifications',
    ar: 'الإشعارات',
    ur: 'اطلاعات',
    hi: 'सूचनाएं',
  );
  static const totalPending = TranslatableString(
    en: 'Total Pending',
    ar: 'إجمالي المعلق',
    ur: 'کل زیر التواء',
    hi: 'कुल लंबित',
  );
  static const urgentAlerts = TranslatableString(
    en: 'Urgent Alerts',
    ar: 'تنبيهات عاجلة',
    ur: 'فوری الرٹس',
    hi: 'अत्यावश्यक अलर्ट',
  );
  static const notificationHealth = TranslatableString(
    en: 'Notification Health',
    ar: 'صحة الإشعارات',
    ur: 'اطلاعات کی کارکردگی',
    hi: 'अधिसूचना स्वास्थ्य',
  );
  static const notificationDetailsUnavailable = TranslatableString(
    en: 'This notification has no available detail link. Its history is preserved.',
    ar: 'لا يتوفر رابط تفاصيل لهذا الإشعار. تم الاحتفاظ بسجله.',
    ur: 'اس اطلاع کی تفصیل کا لنک دستیاب نہیں۔ اس کی تاریخ محفوظ ہے۔',
    hi: 'इस सूचना का विवरण लिंक उपलब्ध नहीं है। इसका इतिहास सुरक्षित है।',
  );
  static const alertsOn = TranslatableString(
    en: 'Device registered for alerts',
    ar: 'الجهاز مسجل للتنبيهات',
    ur: 'ڈیوائس الرٹس کے لیے رجسٹرڈ ہے',
    hi: 'डिवाइस अलर्ट के लिए पंजीकृत है',
  );
  static const alertsOnBody = TranslatableString(
    en: 'Permission is granted. Pop-ups and sound also depend on your browser and system settings.',
    ar: 'تم منح الإذن. يعتمد ظهور التنبيهات والصوت أيضاً على إعدادات المتصفح والنظام.',
    ur: 'اجازت مل گئی ہے۔ پاپ اپ اور آواز براؤزر اور سسٹم کی ترتیبات پر بھی منحصر ہیں۔',
    hi: 'अनुमति मिल गई है। पॉप-अप और ध्वनि ब्राउज़र और सिस्टम सेटिंग पर भी निर्भर हैं।',
  );
  static const enableAlerts = TranslatableString(
    en: 'Enable device alerts',
    ar: 'تفعيل تنبيهات الجهاز',
    ur: 'ڈیوائس الرٹس فعال کریں',
    hi: 'डिवाइस अलर्ट चालू करें',
  );
  static const enableAlertsBody = TranslatableString(
    en: 'Allow Yorks to show workflow and Team Chat alerts even when the app is not open.',
    ar: 'اسمح ليوركس بإظهار تنبيهات سير العمل ومحادثة الفريق حتى عندما لا يكون التطبيق مفتوحاً.',
    ur: 'یورکس کو ورک فلو اور ٹیم چیٹ الرٹس دکھانے دیں، چاہے ایپ کھلی نہ ہو۔',
    hi: 'ऐप बंद होने पर भी यॉर्क्स को कार्यप्रवाह और टीम चैट अलर्ट दिखाने दें।',
  );
  static const alertsBlocked = TranslatableString(
    en: 'Device alerts are blocked',
    ar: 'تنبيهات الجهاز محظورة',
    ur: 'ڈیوائس الرٹس بلاک ہیں',
    hi: 'डिवाइस अलर्ट अवरुद्ध हैं',
  );
  static const alertsBlockedBody = TranslatableString(
    en: 'Allow notifications in the browser or device settings, then check again. In-app alerts remain active.',
    ar: 'اسمح بالإشعارات من إعدادات المتصفح أو الجهاز ثم تحقق مجدداً. تبقى تنبيهات التطبيق مفعلة.',
    ur: 'براؤزر یا ڈیوائس سیٹنگز میں اطلاعات کی اجازت دیں، پھر دوبارہ چیک کریں۔ اِن ایپ الرٹس فعال رہیں گے۔',
    hi: 'ब्राउज़र या डिवाइस सेटिंग में सूचनाएं चालू करें, फिर दोबारा जांचें। इन-ऐप अलर्ट सक्रिय रहेंगे।',
  );
  static const alertsUnavailable = TranslatableString(
    en: 'System alerts are unavailable here',
    ar: 'تنبيهات النظام غير متاحة هنا',
    ur: 'سسٹم الرٹس یہاں دستیاب نہیں',
    hi: 'सिस्टम अलर्ट यहां उपलब्ध नहीं हैं',
  );
  static const alertsUnavailableBody = TranslatableString(
    en: 'In-app workflow and Team Chat alerts remain active.',
    ar: 'تبقى تنبيهات سير العمل ومحادثة الفريق داخل التطبيق مفعلة.',
    ur: 'ایپ کے اندر ورک فلو اور ٹیم چیٹ الرٹس فعال رہیں گے۔',
    hi: 'ऐप के भीतर कार्यप्रवाह और टीम चैट अलर्ट सक्रिय रहेंगे।',
  );
  static const alertSetupNeedsAttention = TranslatableString(
    en: 'Alert setup needs attention',
    ar: 'إعداد التنبيهات يحتاج إلى مراجعة',
    ur: 'الرٹ سیٹ اپ پر توجہ درکار ہے',
    hi: 'अलर्ट सेटअप पर ध्यान आवश्यक है',
  );
  static const alertSetupNeedsAttentionBody = TranslatableString(
    en: 'Check the connection and try again. The notification center still keeps every authorized update.',
    ar: 'تحقق من الاتصال وحاول مجدداً. يحتفظ مركز الإشعارات بكل تحديث مصرح به.',
    ur: 'کنکشن چیک کر کے دوبارہ کوشش کریں۔ نوٹیفکیشن سینٹر ہر مجاز اپ ڈیٹ محفوظ رکھتا ہے۔',
    hi: 'कनेक्शन जांचकर फिर प्रयास करें। सूचना केंद्र हर अधिकृत अपडेट सुरक्षित रखता है।',
  );
  static const checkingAlertDelivery = TranslatableString(
    en: 'Checking alert delivery…',
    ar: 'جارٍ التحقق من تسليم التنبيهات…',
    ur: 'الرٹ ڈیلیوری چیک ہو رہی ہے…',
    hi: 'अलर्ट डिलीवरी जांची जा रही है…',
  );
  static const checkAgain = TranslatableString(
    en: 'Check again',
    ar: 'تحقق مجدداً',
    ur: 'دوبارہ چیک کریں',
    hi: 'फिर जांचें',
  );
  static const recentNotifications = TranslatableString(
    en: 'Recent notifications',
    ar: 'الإشعارات الأخيرة',
    ur: 'حالیہ اطلاعات',
    hi: 'हाल की सूचनाएं',
  );
  static const viewAllNotifications = TranslatableString(
    en: 'View all notifications',
    ar: 'عرض جميع الإشعارات',
    ur: 'تمام اطلاعات دیکھیں',
    hi: 'सभी सूचनाएं देखें',
  );
  static const latestActivity = TranslatableString(
    en: 'Latest Activity',
    ar: 'أحدث النشاطات',
    ur: 'تازہ ترین سرگرمی',
    hi: 'नवीनतम गतिविधि',
  );
  static const markAllRead = TranslatableString(
    en: 'Mark all read',
    ar: 'تحديد الكل كمقروء',
    ur: 'سب پڑھے ہوئے نشان کریں',
    hi: 'सभी पढ़े हुए चिह्नित करें',
  );
  static const allCaughtUp = TranslatableString(
    en: "You're all caught up",
    ar: 'لا توجد إشعارات جديدة',
    ur: 'کوئی نئی اطلاع نہیں',
    hi: 'कोई नई सूचना नहीं',
  );
  static const searchAlerts = TranslatableString(
    en: 'Search system alerts...',
    ar: 'البحث في التنبيهات...',
    ur: 'الرٹس تلاش کریں...',
    hi: 'सिस्टम अलर्ट खोजें...',
  );
  static const filterAllUpper = TranslatableString(
    en: 'ALL',
    ar: 'الكل',
    ur: 'سب',
    hi: 'सभी',
  );
  static const filterUnread = TranslatableString(
    en: 'UNREAD',
    ar: 'غير مقروء',
    ur: 'نہ پڑھے',
    hi: 'अपठित',
  );
  static const filterUrgent = TranslatableString(
    en: 'URGENT',
    ar: 'عاجل',
    ur: 'فوری',
    hi: 'अत्यावश्यक',
  );
  static const filterLast24h = TranslatableString(
    en: 'LAST 24 HOURS',
    ar: 'آخر 24 ساعة',
    ur: 'آخری 24 گھنٹے',
    hi: 'पिछले 24 घंटे',
  );
  static const responseRateUp = TranslatableString(
    en: 'Response rate is up by 12% today',
    ar: 'ارتفعت نسبة الاستجابة بنسبة 12٪ اليوم',
    ur: 'رسپانس کی شرح میں آج 12 فیصد اضافہ ہوا ہے',
    hi: 'आज प्रतिक्रिया दर 12% बढ़ी है',
  );
  static const noNotificationsForFilter = TranslatableString(
    en: 'No notifications match this filter',
    ar: 'لا توجد إشعارات تتطابق مع هذا الفلتر',
    ur: 'اس فلٹر سے کوئی اطلاع مطابقت نہیں رکھتی',
    hi: 'इस फ़िल्टर से कोई सूचना मेल नहीं खाती',
  );
  static const couldNotLoadNotifications = TranslatableString(
    en: 'Could not refresh notifications',
    ar: 'تعذر تحديث الإشعارات',
    ur: 'اطلاعات ریفریش نہیں ہو سکیں',
    hi: 'सूचनाएं रीफ़्रेश नहीं हो सकीं',
  );
  static const retry = TranslatableString(
    en: 'Retry',
    ar: 'إعادة المحاولة',
    ur: 'دوبارہ کوشش کریں',
    hi: 'पुनः प्रयास',
  );

  // ─── Engineer — New Request Form ────────────────────────────────
  static const newRequest = TranslatableString(
    en: 'New Request',
    ar: 'طلب جديد',
    ur: 'نئی درخواست',
    hi: 'नया अनुरोध',
  );
  static const projectName = TranslatableString(
    en: 'Project Name',
    ar: 'اسم المشروع',
    ur: 'پروجیکٹ کا نام',
    hi: 'परियोजना का नाम',
  );
  static const projectNameSecondary = TranslatableString(
    en: 'Name in Secondary Language',
    ar: 'الاسم باللغة الثانوية',
    ur: 'ثانوی زبان میں نام',
    hi: 'द्वितीयक भाषा में नाम',
  );
  static const siteLocation = TranslatableString(
    en: 'Site Location',
    ar: 'موقع الموقع',
    ur: 'سائٹ کا مقام',
    hi: 'साइट स्थान',
  );
  static const numberOfItems = TranslatableString(
    en: 'Number of Items',
    ar: 'عدد العناصر',
    ur: 'اشیاء کی تعداد',
    hi: 'वस्तुओं की संख्या',
  );
  static const priority = TranslatableString(
    en: 'Priority',
    ar: 'الأولوية',
    ur: 'ترجیح',
    hi: 'प्राथमिकता',
  );
  static const undo = TranslatableString(
    en: 'Undo',
    ar: 'تراجع',
    ur: 'واپس',
    hi: 'पूर्ववत',
  );
  static const itemRemoved = TranslatableString(
    en: 'Item removed',
    ar: 'تمت إزالة العنصر',
    ur: 'آئٹم ہٹا دیا گیا',
    hi: 'आइटम हटाया गया',
  );
  static const discardDraft = TranslatableString(
    en: 'Discard draft?',
    ar: 'تجاهل المسودة؟',
    ur: 'مسودہ ضائع کریں؟',
    hi: 'ड्राफ्ट हटाएं?',
  );
  static const discardDraftBody = TranslatableString(
    en: 'This clears the selected project, items and notes.',
    ar: 'سيؤدي هذا إلى مسح المشروع والعناصر والملاحظات المحددة.',
    ur: 'یہ منتخب پروجیکٹ، آئٹمز اور نوٹس صاف کر دے گا۔',
    hi: 'यह चयनित परियोजना, आइटम और नोट्स साफ़ कर देगा।',
  );
  static const draftDiscarded = TranslatableString(
    en: 'Draft discarded',
    ar: 'تم تجاهل المسودة',
    ur: 'مسودہ ضائع کر دیا گیا',
    hi: 'ड्राफ्ट हटा दिया गया',
  );
  static const priorityNormal = TranslatableString(
    en: 'Normal',
    ar: 'عادي',
    ur: 'عام',
    hi: 'सामान्य',
  );
  static const priorityUrgent = TranslatableString(
    en: 'Urgent',
    ar: 'عاجل',
    ur: 'فوری',
    hi: 'अत्यावश्यक',
  );
  static const priorityCritical = TranslatableString(
    en: 'Critical',
    ar: 'حرج',
    ur: 'انتہائی ضروری',
    hi: 'गंभीर',
  );
  static const submitRequest = TranslatableString(
    en: 'Submit Request',
    ar: 'إرسال الطلب',
    ur: 'درخواست جمع کرائیں',
    hi: 'अनुरोध जमा करें',
  );
  static const requestSubmitted = TranslatableString(
    en: 'Request submitted successfully',
    ar: 'تم إرسال الطلب بنجاح',
    ur: 'درخواست کامیابی سے جمع ہو گئی',
    hi: 'अनुरोध सफलतापूर्वक जमा किया गया',
  );
  static const submitShort = TranslatableString(
    en: 'Submit',
    ar: 'إرسال',
    ur: 'جمع کریں',
    hi: 'सबमिट',
  );
  static const submitRequestQuestion = TranslatableString(
    en: 'Submit request?',
    ar: 'إرسال الطلب؟',
    ur: 'درخواست جمع کریں؟',
    hi: 'अनुरोध सबमिट करें?',
  );
  static const submitRequestBody = TranslatableString(
    en: 'This sends the request to procurement and reserves the stock. You can\'t edit it after submitting.',
    ar: 'يرسل هذا الطلب إلى المشتريات ويحجز المخزون. لا يمكنك تعديله بعد الإرسال.',
    ur: 'یہ درخواست پروکیورمنٹ کو بھیجتا ہے اور اسٹاک محفوظ کر دیتا ہے۔ جمع کرانے کے بعد آپ اسے تبدیل نہیں کر سکتے۔',
    hi: 'यह अनुरोध खरीद को भेजता है और स्टॉक आरक्षित करता है। सबमिट के बाद आप इसे संपादित नहीं कर सकते।',
  );
  static const requestNotFound = TranslatableString(
    en: 'Request not found',
    ar: 'الطلب غير موجود',
    ur: 'درخواست نہیں ملی',
    hi: 'अनुरोध नहीं मिला',
  );
  static const noItemsInRequest = TranslatableString(
    en: 'No items in this request',
    ar: 'لا توجد عناصر في هذا الطلب',
    ur: 'اس درخواست میں کوئی آئٹم نہیں',
    hi: 'इस अनुरोध में कोई आइटम नहीं',
  );
  static const deleteDraftBody = TranslatableString(
    en: 'This draft will be permanently removed.',
    ar: 'ستتم إزالة هذه المسودة نهائياً.',
    ur: 'یہ مسودہ مستقل طور پر حذف ہو جائے گا۔',
    hi: 'यह ड्राफ्ट स्थायी रूप से हटा दिया जाएगा।',
  );
  static const enterValidItemCount = TranslatableString(
    en: 'Enter a valid item count',
    ar: 'أدخل عدد عناصر صالح',
    ur: 'ایک درست تعداد درج کریں',
    hi: 'एक मान्य वस्तु संख्या दर्ज करें',
  );

  // ─── Engineer — My Requests (nav label) ─────────────────────────
  static const myRequests = TranslatableString(
    en: 'My Requests',
    ar: 'طلباتي',
    ur: 'میری درخواستیں',
    hi: 'मेरे अनुरोध',
  );

  // ─── Engineer — Request Detail Screen ───────────────────────────
  static const backToRequests = TranslatableString(
    en: 'Back to Requests',
    ar: 'العودة للطلبات',
    ur: 'واپس',
    hi: 'अनुरोधों पर वापस',
  );
  static const requestTimeline = TranslatableString(
    en: 'Request Timeline',
    ar: 'الجدول الزمني للطلب',
    ur: 'درخواست کی ٹائم لائن',
    hi: 'अनुरोध समयरेखा',
  );
  static const materialBreakdown = TranslatableString(
    en: 'Material Breakdown',
    ar: 'تفصيل المواد',
    ur: 'مواد کی تفصیل',
    hi: 'सामग्री विवरण',
  );
  static const verification = TranslatableString(
    en: 'Verification',
    ar: 'التحقق',
    ur: 'تصدیق',
    hi: 'सत्यापन',
  );
  static const totalValueLabel = TranslatableString(
    en: 'TOTAL VALUE',
    ar: 'القيمة الإجمالية',
    ur: 'کل مالیت',
    hi: 'कुल मूल्य',
  );
  static const issueDateLabel = TranslatableString(
    en: 'ISSUE DATE',
    ar: 'تاريخ الإصدار',
    ur: 'تاریخ اجراء',
    hi: 'जारी तिथि',
  );
  static const downloadReceipt = TranslatableString(
    en: 'Download Receipt',
    ar: 'تحميل الإيصال',
    ur: 'رسید ڈاؤن لوڈ کریں',
    hi: 'रसीद डाउनलोड करें',
  );
  static const printOrder = TranslatableString(
    en: 'Print Order',
    ar: 'طباعة الطلب',
    ur: 'پرنٹ کریں',
    hi: 'ऑर्डर प्रिंट करें',
  );
  static const couldNotOpenReceipt = TranslatableString(
    en: 'Could not open receipt',
    ar: 'تعذّر فتح الإيصال',
    ur: 'رسید نہیں کھل سکی',
    hi: 'रसीद नहीं खुल सकी',
  );
  static const requestCreated = TranslatableString(
    en: 'Request Created',
    ar: 'تم إنشاء الطلب',
    ur: 'درخواست بنائی گئی',
    hi: 'अनुरोध बनाया गया',
  );
  static const stockValidated = TranslatableString(
    en: 'Stock Validated',
    ar: 'تم التحقق من المخزون',
    ur: 'اسٹاک کی تصدیق ہو گئی',
    hi: 'स्टॉक सत्यापित',
  );
  static const requestDeployed = TranslatableString(
    en: 'Request Deployed',
    ar: 'تم نشر الطلب',
    ur: 'درخواست مکمل کر دی گئی ہے',
    hi: 'अनुरोध तैनात',
  );
  static const issuedBy = TranslatableString(
    en: 'ISSUED BY',
    ar: 'صدر بواسطة',
    ur: 'جاری کنندہ',
    hi: 'जारीकर्ता',
  );
  static const requestedBy = TranslatableString(
    en: 'REQUESTED BY',
    ar: 'مطلوب بواسطة',
    ur: 'درخواست کنندہ',
    hi: 'अनुरोधकर्ता',
  );
  static const warehouseParty = TranslatableString(
    en: 'Warehouse',
    ar: 'المستودع',
    ur: 'گودام',
    hi: 'गोदाम',
  );
  static const notIssuedYet = TranslatableString(
    en: 'Not issued yet',
    ar: 'لم يصدر بعد',
    ur: 'ابھی جاری نہیں',
    hi: 'अभी जारी नहीं',
  );
  static const reqQty = TranslatableString(
    en: 'REQ QTY',
    ar: 'الكمية المطلوبة',
    ur: 'درخواست',
    hi: 'अनुरोधित मात्रा',
  );
  static const issuedQty = TranslatableString(
    en: 'ISSUED QTY',
    ar: 'الكمية الصادرة',
    ur: 'جاری کردہ',
    hi: 'जारी मात्रा',
  );
  static const unitPriceLabel = TranslatableString(
    en: 'UNIT PRICE',
    ar: 'سعر الوحدة',
    ur: 'فی اکائی قیمت',
    hi: 'इकाई मूल्य',
  );
  static const itemLabel = TranslatableString(
    en: 'ITEM',
    ar: 'العنصر',
    ur: 'آئٹم',
    hi: 'वस्तु',
  );
  static const budgetCode = TranslatableString(
    en: 'Budget Code',
    ar: 'رمز الميزانية',
    ur: 'بجٹ کوڈ',
    hi: 'बजट कोड',
  );
  static const categories = TranslatableString(
    en: 'Categories',
    ar: 'الفئات',
    ur: 'زمرے',
    hi: 'श्रेणियाँ',
  );
  static const updated = TranslatableString(
    en: 'Updated',
    ar: 'محدث',
    ur: 'اپ ڈیٹ',
    hi: 'अपडेट',
  );

  // ─── Browse Materials Screen ───────────────────────────────────
  static const totalItemsInStock = TranslatableString(
    en: 'Total Items in Stock',
    ar: 'إجمالي العناصر في المخزون',
    ur: 'اسٹاک میں کل اشیاء',
    hi: 'स्टॉक में कुल आइटम',
  );
  static const activeCategories = TranslatableString(
    en: 'Active',
    ar: 'نشط',
    ur: 'فعال زمرے',
    hi: 'सक्रिय',
  );
  static const allMaterials = TranslatableString(
    en: 'All Materials',
    ar: 'جميع المواد',
    ur: 'تمام مواد',
    hi: 'सभी सामग्री',
  );
  static const concrete = TranslatableString(
    en: 'Concrete',
    ar: 'الخرسانة',
    ur: 'کنکریٹ',
    hi: 'कंक्रीट',
  );
  static const steel = TranslatableString(
    en: 'Steel',
    ar: 'الفولاذ',
    ur: 'سٹیل',
    hi: 'स्टील',
  );
  static const finishing = TranslatableString(
    en: 'Finishing',
    ar: 'التشطيب',
    ur: 'فنشنگ',
    hi: 'फिनिशिंग',
  );

  // ─── HVAC Browse Filters ───────────────────────────────────────
  static const valvesFittings = TranslatableString(
    en: 'Valves & Fittings',
    ar: 'الصمامات والتوصيلات',
    ur: 'والوز اور فٹنگز',
    hi: 'वाल्व और फिटिंग्स',
  );
  static const pipesDucts = TranslatableString(
    en: 'Pipes & Ducts',
    ar: 'الأنابيب والقنوات',
    ur: 'پائپ اور ڈکٹس',
    hi: 'पाइप और डक्ट',
  );
  static const fastenersTools = TranslatableString(
    en: 'Fasteners & Tools',
    ar: 'المثبتات والأدوات',
    ur: 'نٹ بولٹ اور اوزار',
    hi: 'फास्टनर और उपकरण',
  );
  static const stockLevel = TranslatableString(
    en: 'STOCK LEVEL',
    ar: 'مستوى المخزون',
    ur: 'اسٹاک کی سطح',
    hi: 'स्टॉक स्तर',
  );
  static const actions = TranslatableString(
    en: 'ACTIONS',
    ar: 'الإجراءات',
    ur: 'اعمال',
    hi: 'कार्रवाई',
  );
  static const addToRequest = TranslatableString(
    en: 'Add to\nRequest',
    ar: 'أضف إلى\nالطلب',
    ur: 'شامل\nکریں',
    hi: 'अनुरोध में\nजोड़ें',
  );
  static const addLabel = TranslatableString(
    en: 'Add',
    ar: 'أضف',
    ur: 'شامل',
    hi: 'जोड़ें',
  );
  static const added = TranslatableString(
    en: 'Added',
    ar: 'تمت الإضافة',
    ur: 'شامل ہو گیا',
    hi: 'जोड़ा गया',
  );
  static const done = TranslatableString(
    en: 'Done',
    ar: 'تم',
    ur: 'ہو گیا',
    hi: 'हो गया',
  );
  static const healthy = TranslatableString(
    en: 'HEALTHY',
    ar: 'سليم',
    ur: 'صحت مند',
    hi: 'स्वस्थ',
  );
  static const moderate = TranslatableString(
    en: 'MODERATE',
    ar: 'متوسط',
    ur: 'معتدل',
    hi: 'मध्यम',
  );
  static const remaining = TranslatableString(
    en: 'remaining',
    ar: 'متبقي',
    ur: 'باقی',
    hi: 'शेष',
  );
  static const showing = TranslatableString(
    en: 'Showing',
    ar: 'عرض',
    ur: 'دکھا رہا ہے',
    hi: 'दिखा रहा है',
  );
  static const of_ = TranslatableString(
    en: 'of',
    ar: 'من',
    ur: 'میں سے',
    hi: 'में से',
  );
  static const previous = TranslatableString(
    en: 'Previous',
    ar: 'السابق',
    ur: 'پچھلا',
    hi: 'पिछला',
  );
  static const next = TranslatableString(
    en: 'Next',
    ar: 'التالي',
    ur: 'اگلا',
    hi: 'अगला',
  );
  static const thisMonth = TranslatableString(
    en: 'This Month',
    ar: 'هذا الشهر',
    ur: 'اس ماہ',
    hi: 'इस महीने',
  );
  static const needRestockLabel = TranslatableString(
    en: 'need restock',
    ar: 'بحاجة لإعادة تخزين',
    ur: 'ری اسٹاک درکار',
    hi: 'रीस्टॉक चाहिए',
  );
  static const allHealthy = TranslatableString(
    en: 'Stock healthy',
    ar: 'المخزون جيد',
    ur: 'اسٹاک ٹھیک',
    hi: 'स्टॉक ठीक',
  );
  static const searchInventory = TranslatableString(
    en: 'Search inventory...',
    ar: 'ابحث في المخزون...',
    ur: 'انوینٹری تلاش کریں۔۔۔',
    hi: 'इन्वेंटरी खोजें...',
  );

  // ─── New Request / Create Material Requisition ─────────────────
  static const createMaterialRequisition = TranslatableString(
    en: 'CREATE MATERIAL REQUISITION',
    ar: 'إنشاء طلب مواد',
    ur: 'مواد کی درخواست بنائیں',
    hi: 'सामग्री मांग पत्र बनाएं',
  );
  static const createReqSubtitle = TranslatableString(
    en: 'Submit a new inventory request for your current project site.',
    ar: 'قدم طلب جرد جديد لموقع مشروعك الحالي.',
    ur: 'نئی میٹیریل کی درخواست جمع کروائیں',
    hi: 'अपनी वर्तमान परियोजना स्थल के लिए नई इन्वेंटरी अनुरोध जमा करें।',
  );
  static const selectProject = TranslatableString(
    en: 'Select Project',
    ar: 'اختر المشروع',
    ur: 'پروجیکٹ منتخب کریں',
    hi: 'परियोजना चुनें',
  );
  static const generalNotes = TranslatableString(
    en: 'General Notes',
    ar: 'ملاحظات عامة',
    ur: 'عمومی نوٹس',
    hi: 'सामान्य टिप्पणियाँ',
  );
  static const generalNotesPlaceholder = TranslatableString(
    en: 'Describe priority or special handling...',
    ar: 'صف الأولوية أو المعاملة الخاصة...',
    ur: 'ترجیح یا خاص ہدایات بیان کریں...',
    hi: 'प्राथमिकता या विशेष हैंडलिंग का वर्णन करें...',
  );
  static const generalNotesHelper = TranslatableString(
    en: 'Include any urgent site conditions or delivery restrictions.',
    ar: 'قم بتضمين أي ظروف موقع عاجلة أو قيود التسليم.',
    ur: 'ترسیل کی کسی بھی فوری شرط یا پابندی کا ذکر کریں۔',
    hi: 'किसी भी तत्काल साइट स्थिति या वितरण प्रतिबंध शामिल करें।',
  );
  static const stockAvailability = TranslatableString(
    en: 'Stock Availability',
    ar: 'توفر المخزون',
    ur: 'اسٹاک کی دستیابی',
    hi: 'स्टॉक उपलब्धता',
  );
  static const stockAvailabilityDesc = TranslatableString(
    en: 'System will automatically check central warehouse stock levels upon submission.',
    ar: 'سيقوم النظام تلقائيًا بفحص مستويات المخزون عند التقديم.',
    ur: 'سسٹم جمع کرانے پر خودکار طریقے سے مرکزی گودام کے اسٹاک کی جانچ کرے گا۔',
    hi: 'सिस्टम जमा करने पर स्वचालित रूप से केंद्रीय गोदाम स्टॉक स्तरों की जाँच करेगा।',
  );
  static const requestedItems = TranslatableString(
    en: 'Requested Items',
    ar: 'العناصر المطلوبة',
    ur: 'درخواست شدہ اشیاء',
    hi: 'अनुरोधित आइटम',
  );
  static const addNewItem = TranslatableString(
    en: 'Add New Item',
    ar: 'أضف عنصرًا جديدًا',
    ur: 'نئی چیز شامل کریں',
    hi: 'नया आइटम जोड़ें',
  );
  static const addMoreItems = TranslatableString(
    en: 'Add more items by clicking the button above.',
    ar: 'أضف المزيد من العناصر بالنقر على الزر أعلاه.',
    ur: 'اوپر والے بٹن پر کلک کر کے مزید اشیاء شامل کریں۔',
    hi: 'ऊपर के बटन पर क्लिक करके और आइटम जोड़ें।',
  );
  static const saveAsDraft = TranslatableString(
    en: 'Save as Draft',
    ar: 'حفظ كمسودة',
    ur: 'ڈرافٹ محفوظ کریں',
    hi: 'ड्राफ्ट के रूप में सहेजें',
  );
  static const action = TranslatableString(
    en: 'ACTION',
    ar: 'إجراء',
    ur: 'عمل',
    hi: 'कार्रवाई',
  );
  static const selectProjectRequired = TranslatableString(
    en: 'Please select a project',
    ar: 'يرجى اختيار مشروع',
    ur: 'براہ کرم ایک پروجیکٹ منتخب کریں',
    hi: 'कृपया एक परियोजना चुनें',
  );
  static const addAtLeastOneItem = TranslatableString(
    en: 'Please add at least one item',
    ar: 'يرجى إضافة عنصر واحد على الأقل',
    ur: 'براہ کرم کم از کم ایک آئٹم شامل کریں',
    hi: 'कृपया कम से कम एक आइटम जोड़ें',
  );
  static const browseMaterials = TranslatableString(
    en: 'Browse Materials',
    ar: 'تصفح المواد',
    ur: 'مواد دیکھیں',
    hi: 'सामग्री ब्राउज़ करें',
  );
  static const quickAction = TranslatableString(
    en: 'Quick Action',
    ar: 'إجراء سريع',
    ur: 'فوری عمل',
    hi: 'त्वरित कार्रवाई',
  );

  // ─── New Request Screen (Redesigned) ────────────────────────────
  static const newMaterialRequest = TranslatableString(
    en: 'New Material Request',
    ar: 'طلب مواد جديد',
    ur: 'میٹیریل کی نئی درخواست',
    hi: 'नई सामग्री अनुरोध',
  );
  static const selectedItems = TranslatableString(
    en: 'Selected Items',
    ar: 'العناصر المختارة',
    ur: 'منتخب اشیاء',
    hi: 'चयनित आइटम',
  );
  static const browseAndAddMore = TranslatableString(
    en: 'Browse & Add More',
    ar: 'تصفح وأضف المزيد',
    ur: 'مزید اشیاء شامل کریں',
    hi: 'ब्राउज़ करें और जोड़ें',
  );
  static const additionalNotesOptional = TranslatableString(
    en: 'Additional Notes (Optional)',
    ar: 'ملاحظات إضافية (اختياري)',
    ur: 'اضافی نوٹ (اختیاری)',
    hi: 'अतिरिक्त नोट्स (वैकल्पिक)',
  );
  static const submitRequisition = TranslatableString(
    en: 'Submit Requisition',
    ar: 'تقديم الطلب',
    ur: 'درخواست جمع کروائیں',
    hi: 'मांग पत्र जमा करें',
  );
  static const theLedger = TranslatableString(
    en: 'The Ledger',
    ar: 'دفتر الطلبات',
    ur: 'درخواست لیجر',
    hi: 'लेजर',
  );
  static const projectTag = TranslatableString(
    en: 'Project Tag',
    ar: 'علامة المشروع',
    ur: 'پروجیکٹ ٹیگ',
    hi: 'प्रोजेक्ट टैग',
  );
  static const priorityLevel = TranslatableString(
    en: 'Priority Level',
    ar: 'مستوى الأولوية',
    ur: 'ترجیحی سطح',
    hi: 'प्राथमिकता स्तर',
  );
  static const allItems = TranslatableString(
    en: 'ALL ITEMS',
    ar: 'كل العناصر',
    ur: 'تمام اشیاء',
    hi: 'सभी आइटम',
  );
  static const availableFilter = TranslatableString(
    en: 'AVAILABLE',
    ar: 'متاح',
    ur: 'دستیاب',
    hi: 'उपलब्ध',
  );
  static const lowStockFilter = TranslatableString(
    en: 'LOW STOCK',
    ar: 'مخزون منخفض',
    ur: 'کم اسٹاک',
    hi: 'कम स्टॉक',
  );
  static const searchMaterials = TranslatableString(
    en: 'Search Materials...',
    ar: 'ابحث عن المواد...',
    ur: 'اشیاء تلاش کریں...',
    hi: 'सामग्री खोजें...',
  );
  static const materialOps = TranslatableString(
    en: 'Material Ops',
    ar: 'عمليات المواد',
    ur: 'مواد آپریشنز',
    hi: 'सामग्री संचालन',
  );
  static const engineersPortal = TranslatableString(
    en: 'Engineers Portal',
    ar: 'بوابة المهندسين',
    ur: 'انجینئرز پورٹل',
    hi: 'इंजीनियर पोर्टल',
  );

  static const structure = TranslatableString(
    en: 'STRUCTURE',
    ar: 'الهيكل',
    ur: 'ساخت',
    hi: 'संरचना',
  );
  static const support = TranslatableString(
    en: 'Support',
    ar: 'الدعم',
    ur: 'مدد',
    hi: 'सहायता',
  );
  static const signOut = TranslatableString(
    en: 'Sign Out',
    ar: 'تسجيل الخروج',
    ur: 'سائن آؤٹ',
    hi: 'साइन आउट',
  );
  static const itemsSelected = TranslatableString(
    en: 'Items Selected',
    ar: 'عناصر مختارة',
    ur: 'آئٹمز منتخب',
    hi: 'आइटम चयनित',
  );
  static const normal = TranslatableString(
    en: 'Normal',
    ar: 'عادي',
    ur: 'عام',
    hi: 'सामान्य',
  );
  static const high = TranslatableString(
    en: 'High',
    ar: 'عالي',
    ur: 'زیادہ',
    hi: 'उच्च',
  );
  static const urgent = TranslatableString(
    en: 'Urgent',
    ar: 'عاجل',
    ur: 'فوری',
    hi: 'अत्यावश्यक',
  );

  // ─── Draft ──────────────────────────────────────────────────────
  static const draftSaved = TranslatableString(
    en: 'Draft saved successfully',
    ar: 'تم حفظ المسودة بنجاح',
    ur: 'ڈرافٹ کامیابی سے محفوظ ہو گیا',
    hi: 'ड्राफ्ट सफलतापूर्वक सहेजा गया',
  );
  static const statusDraft = TranslatableString(
    en: 'DRAFT',
    ar: 'مسودة',
    ur: 'مسودہ',
    hi: 'ड्राफ्ट',
  );
  static const resumeDraft = TranslatableString(
    en: 'Resume Draft',
    ar: 'استئناف المسودة',
    ur: 'ڈرافٹ جاری رکھیں',
    hi: 'ड्राफ्ट जारी रखें',
  );
  static const deleteDraft = TranslatableString(
    en: 'Delete Draft',
    ar: 'حذف المسودة',
    ur: 'ڈرافٹ حذف کریں',
    hi: 'ड्राफ्ट हटाएं',
  );
  static const draftRequests = TranslatableString(
    en: 'Drafts',
    ar: 'المسودات',
    ur: 'ڈرافٹس',
    hi: 'ड्राफ्ट',
  );
  static const requestDeletedSuccess = TranslatableString(
    en: 'Request deleted',
    ar: 'تم حذف الطلب',
    ur: 'درخواست حذف ہو گئی',
    hi: 'अनुरोध हटाया गया',
  );

  // ─── About Screen ───────────────────────────────────────────────
  static const aboutDescription = TranslatableString(
    en: 'About Yorks AC. & Ref.',
    ar: 'حول Yorks AC. & Ref.',
    ur: 'Yorks AC. & Ref. کے بارے میں',
    hi: 'Yorks AC. & Ref. के बारे में',
  );
  static const aboutBody = TranslatableString(
    en: 'Yorks AC. & Ref. is the controlled workspace for projects, materials, procurement and documents. It helps engineers, procurement and management coordinate traceable work across projects.',
    ar: 'Yorks AC. & Ref. هي مساحة العمل المنضبطة للمشاريع والمواد والمشتريات والمستندات. وهي تساعد المهندسين والمشتريات والإدارة على تنسيق العمل القابل للتتبع عبر المشاريع.',
    ur: 'Yorks AC. & Ref. منصوبوں، مواد، خریداری اور دستاویزات کے لیے منظم ورک اسپیس ہے۔ یہ انجینئرز، پروکیورمنٹ اور انتظامیہ کو منصوبوں میں قابلِ سراغ کام ہم آہنگ کرنے میں مدد دیتی ہے۔',
    hi: 'Yorks AC. & Ref. परियोजनाओं, सामग्री, खरीद और दस्तावेज़ों के लिए नियंत्रित कार्यक्षेत्र है। यह इंजीनियरिंग, खरीद और प्रबंधन को परियोजनाओं में पता लगाने योग्य काम समन्वित करने में मदद करता है।',
  );
  static const aboutFramework = TranslatableString(
    en: 'Framework',
    ar: 'إطار العمل',
    ur: 'فریم ورک',
    hi: 'फ्रेमवर्क',
  );
  static const aboutDesignSystem = TranslatableString(
    en: 'Design System',
    ar: 'نظام التصميم',
    ur: 'ڈیزائن سسٹم',
    hi: 'डिज़ाइन सिस्टम',
  );
  static const aboutLanguages = TranslatableString(
    en: 'Languages',
    ar: 'اللغات',
    ur: 'زبانیں',
    hi: 'भाषाएं',
  );
  static const aboutDeveloper = TranslatableString(
    en: 'Developer',
    ar: 'المطور',
    ur: 'ڈویلپر',
    hi: 'डेवलपर',
  );
  static const privacyPolicy = TranslatableString(
    en: 'Privacy Policy',
    ar: 'سياسة الخصوصية',
    ur: 'رازداری کی پالیسی',
    hi: 'गोपनीयता नीति',
  );
  static const termsOfService = TranslatableString(
    en: 'Terms of Service',
    ar: 'شروط الخدمة',
    ur: 'سروس کی شرائط',
    hi: 'सेवा की शर्तें',
  );
  static const openSourceLicenses = TranslatableString(
    en: 'Open Source Licenses',
    ar: 'تراخيص المصادر المفتوحة',
    ur: 'اوپن سورس لائسنس',
    hi: 'ओपन सोर्स लाइसेंस',
  );
  // ─── Engineer Dashboard (Architectural Ledger) ──────────────────
  static const engineeringPrecision = TranslatableString(
    en: 'Engineering Precision',
    ar: 'الدقة الهندسية',
    ur: 'انجینئرنگ کی درستگی',
    hi: 'इंजीनियरिंग परिशुद्धता',
  );
  static const searchParameters = TranslatableString(
    en: 'Search parameters...',
    ar: 'ابحث في المعايير...',
    ur: 'سرچ پیرامیٹرز...',
    hi: 'पैरामीटर खोजें...',
  );
  static const projectSwitcher = TranslatableString(
    en: 'Project Switcher',
    ar: 'محوّل المشاريع',
    ur: 'پروجیکٹ سونچر',
    hi: 'प्रोजेक्ट स्विचर',
  );
  static const phase = TranslatableString(
    en: 'Phase',
    ar: 'مرحلة',
    ur: 'فیز',
    hi: 'चरण',
  );
  static const planReadyForApproval = TranslatableString(
    en: 'Plan ready for your approval',
    ar: 'الخطة جاهزة لموافقتك',
    ur: 'آپ کی منظوری کے لیے پلان تیار ہے',
    hi: 'योजना आपकी स्वीकृति के लिए तैयार है',
  );
  static const activeProjects = TranslatableString(
    en: 'Active projects',
    ar: 'المشاريع النشطة',
    ur: 'فعال پروجیکٹس',
    hi: 'सक्रिय परियोजनाएं',
  );
  static const actionsNeeded = TranslatableString(
    en: 'Actions needed',
    ar: 'إجراءات مطلوبة',
    ur: 'اقدامات درکار ہیں',
    hi: 'कार्रवाई आवश्यक',
  );
  static const openRequests = TranslatableString(
    en: 'Open requests',
    ar: 'طلبات مفتوحة',
    ur: 'کھلی درخواستیں',
    hi: 'खुले अनुरोध',
  );
  static const myProjects = TranslatableString(
    en: 'My projects',
    ar: 'مشاريعي',
    ur: 'میرے پروجیکٹس',
    hi: 'मेरी परियोजनाएं',
  );
  static const projects = TranslatableString(
    en: 'Projects',
    ar: 'المشاريع',
    ur: 'پروجیکٹس',
    hi: 'परियोजनाएं',
  );
  static const addAnotherProject = TranslatableString(
    en: 'Add another project',
    ar: 'إضافة مشروع آخر',
    ur: 'ایک اور پروجیکٹ شامل کریں',
    hi: 'एक और परियोजना जोड़ें',
  );
  static const createProject = TranslatableString(
    en: 'Create project',
    ar: 'إنشاء مشروع',
    ur: 'پروجیکٹ بنائیں',
    hi: 'परियोजना बनाएं',
  );
  static const projectCreated = TranslatableString(
    en: 'Project created',
    ar: 'تم إنشاء المشروع',
    ur: 'پروجیکٹ بن گیا',
    hi: 'परियोजना बनाई गई',
  );
  static const buildingName = TranslatableString(
    en: 'Building Name',
    ar: 'اسم المبنى',
    ur: 'عمارت کا نام',
    hi: 'भवन का नाम',
  );
  static const floorNumbers = TranslatableString(
    en: 'Floor Numbers',
    ar: 'أرقام الطوابق',
    ur: 'فلور نمبرز',
    hi: 'फर्श संख्या',
  );
  static const startDate = TranslatableString(
    en: 'Start Date',
    ar: 'تاريخ البدء',
    ur: 'شروع کرنے کی تاریخ',
    hi: 'प्रारंभ तिथि',
  );
  static const expectedEndDate = TranslatableString(
    en: 'Expected End Date',
    ar: 'تاريخ الانتهاء المتوقع',
    ur: 'متوقع ختم ہونے کی تاریخ',
    hi: 'अपेक्षित समाप्ति तिथि',
  );
  static const siteNotes = TranslatableString(
    en: 'Site Notes',
    ar: 'ملاحظات الموقع',
    ur: 'سائٹ نوٹس',
    hi: 'Site Notes',
  );
  static const clientName = TranslatableString(
    en: 'Client Name',
    ar: 'اسم العميل',
    ur: 'کلائنٹ کا نام',
    hi: 'ग्राहक का नाम',
  );
  static const clientNameRequired = TranslatableString(
    en: 'Client name is required',
    ar: 'اسم العميل مطلوب',
    ur: 'کلائنٹ کا نام ضروری ہے',
    hi: 'ग्राहक का नाम आवश्यक है',
  );
  static const locationRequired = TranslatableString(
    en: 'Location is required',
    ar: 'الموقع مطلوب',
    ur: 'مقام ضروری ہے',
    hi: 'स्थान आवश्यक है',
  );
  static const buildingNameRequired = TranslatableString(
    en: 'Building name is required',
    ar: 'اسم المبنى مطلوب',
    ur: 'عمارت کا نام ضروری ہے',
    hi: 'भवन का नाम आवश्यक है',
  );
  static const floorNumbersRequired = TranslatableString(
    en: 'Floor numbers are required',
    ar: 'أرقام الطوابق مطلوبة',
    ur: 'فلور نمبرز ضروری ہیں',
    hi: 'फर्श संख्या आवश्यक है',
  );
  static const startDateRequired = TranslatableString(
    en: 'Start date is required',
    ar: 'تاريخ البدء مطلوب',
    ur: 'شروع کرنے کی تاریخ ضروری ہے',
    hi: 'प्रारंभ तिथि आवश्यक है',
  );
  static const totalLabel = TranslatableString(
    en: 'total',
    ar: 'الإجمالي',
    ur: 'کل',
    hi: 'कुल',
  );
  static const filterAllShort = TranslatableString(
    en: 'All',
    ar: 'الكل',
    ur: 'سب',
    hi: 'सभी',
  );
  static const filterActive = TranslatableString(
    en: 'Active',
    ar: 'نشط',
    ur: 'فعال',
    hi: 'सक्रिय',
  );
  static const filterPlanning = TranslatableString(
    en: 'Planning',
    ar: 'تخطيط',
    ur: 'منصوبہ بندی',
    hi: 'योजना',
  );
  static const filterOnHold = TranslatableString(
    en: 'On hold',
    ar: 'متوقف',
    ur: 'رکا ہوا',
    hi: 'रुका हुआ',
  );
  static const filterCompleted = TranslatableString(
    en: 'Completed',
    ar: 'مكتمل',
    ur: 'مکمل',
    hi: 'पूर्ण',
  );
  static const approvePlan = TranslatableString(
    en: 'Approve plan',
    ar: 'الموافقة على الخطة',
    ur: 'پلان منظور کریں',
    hi: 'योजना स्वीकृत करें',
  );
  static const allDispatched = TranslatableString(
    en: 'All dispatched',
    ar: 'تم إرسال الكل',
    ur: 'سب بھیج گئے',
    hi: 'सभी भेजे गए',
  );
  static const updatedAgo = TranslatableString(
    en: 'Updated',
    ar: 'تم التحديث',
    ur: 'اپڈیٹ',
    hi: 'अपडेट',
  );
  static const materialFeed = TranslatableString(
    en: 'Material Feed',
    ar: 'تدفق المواد',
    ur: 'میٹیریل فیڈ',
    hi: 'सामग्री फ़ीड',
  );
  static const realTimeDispatches = TranslatableString(
    en: 'Real-time dispatches',
    ar: 'إرساليات فورية',
    ur: 'ریئل ٹائم ڈسپیچز',
    hi: 'रीयल-टाइम प्रेषण',
  );
  static const viewLogisticsHistory = TranslatableString(
    en: 'View Logistics History',
    ar: 'عرض سجل اللوجستيات',
    ur: 'لاجسٹکس کی تاریخ دیکھیں',
    hi: 'लॉजिस्टिक्स इतिहास देखें',
  );
  static const dispatchTo = TranslatableString(
    en: 'To',
    ar: 'إلى',
    ur: 'کی طرف',
    hi: 'को',
  );
  static const dispatchAssigned = TranslatableString(
    en: 'Assigned',
    ar: 'مُعيَّن',
    ur: 'تفویض شدہ',
    hi: 'सौंपा गया',
  );
  static const noProjectsInFilter = TranslatableString(
    en: 'No projects in this filter',
    ar: 'لا توجد مشاريع في هذا الفلتر',
    ur: 'اس فلٹر میں کوئی پروجیکٹ نہیں',
    hi: 'इस फ़िल्टर में कोई परियोजना नहीं',
  );
  static const showAll = TranslatableString(
    en: 'Show all',
    ar: 'عرض الكل',
    ur: 'سب دکھائیں',
    hi: 'सभी दिखाएं',
  );
  static const openRequestsLabel = TranslatableString(
    en: 'open requests',
    ar: 'طلبات مفتوحة',
    ur: 'کھلی درخواستیں',
    hi: 'खुले अनुरोध',
  );
  static const minuteAbbrev = TranslatableString(
    en: 'm ago',
    ar: 'د مضت',
    ur: 'منٹ پہلے',
    hi: 'मिनट पहले',
  );
  static const hourAbbrev = TranslatableString(
    en: 'h ago',
    ar: 'س مضت',
    ur: 'گھنٹے پہلے',
    hi: 'घंटे पहले',
  );
  static const dayAbbrev = TranslatableString(
    en: 'd ago',
    ar: 'ي مضت',
    ur: 'دن پہلے',
    hi: 'दिन पहले',
  );
  static const justNow = TranslatableString(
    en: 'just now',
    ar: 'الآن',
    ur: 'ابھی',
    hi: 'अभी',
  );

  // ─── Phase 1 — Material Plan ──────────────────────────────
  static const planReview = TranslatableString(
    en: 'Plan review',
    ar: 'مراجعة الخطة',
    ur: 'منصوبے کا جائزہ',
    hi: 'योजना समीक्षा',
  );
  static const planReviewSubtitle = TranslatableString(
    en: 'Procurement arranged your plan. Approve to move the project to Active.',
    ar: 'قامت المشتريات بترتيب خطتك. وافق لتفعيل المشروع.',
    ur: 'پروکیورمنٹ نے آپ کا منصوبہ تیار کر دیا۔ پروجیکٹ فعال کرنے کے لیے منظور کریں۔',
    hi: 'खरीद ने आपकी योजना तैयार कर दी। प्रोजेक्ट सक्रिय करने हेतु अनुमोदित करें।',
  );
  static const planItems = TranslatableString(
    en: 'Plan items',
    ar: 'بنود الخطة',
    ur: 'منصوبے کی اشیاء',
    hi: 'योजना आइटम',
  );
  static const requestChanges = TranslatableString(
    en: 'Request changes',
    ar: 'طلب تغييرات',
    ur: 'تبدیلیاں طلب کریں',
    hi: 'बदलाव का अनुरोध',
  );
  static const selectItemsToChange = TranslatableString(
    en: 'Tap items that need changes, then add a note.',
    ar: 'اضغط على البنود التي تحتاج تغييراً ثم أضف ملاحظة.',
    ur: 'جن اشیاء میں تبدیلی درکار ہے انہیں منتخب کریں، پھر نوٹ لکھیں۔',
    hi: 'जिन आइटम में बदलाव चाहिए उन्हें चुनें, फिर नोट जोड़ें।',
  );
  static const planApproved = TranslatableString(
    en: 'Plan approved — project is now Active',
    ar: 'تمت الموافقة — المشروع نشط الآن',
    ur: 'منصوبہ منظور — پروجیکٹ اب فعال ہے',
    hi: 'योजना अनुमोदित — प्रोजेक्ट अब सक्रिय है',
  );
  static const acceptProject = TranslatableString(
    en: 'Accept project',
    ar: 'قبول المشروع',
    ur: 'پروجیکٹ قبول کریں',
    hi: 'परियोजना स्वीकार करें',
  );
  static const acceptProjectConfirmTitle = TranslatableString(
    en: 'Accept this project?',
    ar: 'قبول هذا المشروع؟',
    ur: 'یہ پروجیکٹ قبول کریں؟',
    hi: 'यह परियोजना स्वीकार करें?',
  );
  static const acceptProjectConfirmBody = TranslatableString(
    en: 'Confirms procurement is now tracking this job for material supply. The assigned engineer will be notified.',
    ar: 'يؤكد أن المشتريات تتابع الآن هذا العمل لتوريد المواد. سيتم إخطار المهندس المكلف.',
    ur: 'اس سے تصدیق ہوتی ہے کہ پروکیورمنٹ اب اس کام کو مواد کی فراہمی کے لیے ٹریک کر رہا ہے۔ متعلقہ انجینئر کو مطلع کیا جائے گا۔',
    hi: 'यह पुष्टि करता है कि खरीद अब इस काम को सामग्री आपूर्ति हेतु ट्रैक कर रही है। नियुक्त इंजीनियर को सूचित किया जाएगा।',
  );
  static const projectAccepted = TranslatableString(
    en: 'Project accepted',
    ar: 'تم قبول المشروع',
    ur: 'پروجیکٹ قبول ہو گیا',
    hi: 'परियोजना स्वीकृत',
  );
  static const awaitingProcurementChip = TranslatableString(
    en: 'Awaiting procurement',
    ar: 'بانتظار المشتريات',
    ur: 'پروکیورمنٹ کے منتظر',
    hi: 'खरीद की प्रतीक्षा में',
  );
  static const markDoneConfirmTitle = TranslatableString(
    en: 'Mark this plan Done?',
    ar: 'وضع علامة إنجاز على هذه الخطة؟',
    ur: 'اس پلان کو مکمل نشان زد کریں؟',
    hi: 'इस योजना को पूर्ण चिह्नित करें?',
  );
  static const markDoneConfirmBody = TranslatableString(
    en: 'Sends the plan back to the engineer for final approval. Make sure every item is really arranged first.',
    ar: 'يعيد الخطة إلى المهندس للموافقة النهائية. تأكد أولاً أن كل بند تم ترتيبه فعليًا.',
    ur: 'پلان کو حتمی منظوری کے لیے انجینئر کو واپس بھیجتا ہے۔ پہلے یقینی بنائیں ہر آئٹم واقعی بندوبست ہو چکا ہے۔',
    hi: 'योजना अंतिम अनुमोदन हेतु इंजीनियर को वापस भेजता है। पहले सुनिश्चित करें कि हर आइटम वाकई व्यवस्थित है।',
  );
  static const enterQuantityToReceive = TranslatableString(
    en: 'Enter a quantity greater than 0 to receive.',
    ar: 'أدخل كمية أكبر من 0 للاستلام.',
    ur: 'وصول کے لیے 0 سے زیادہ مقدار درج کریں۔',
    hi: 'प्राप्त करने हेतु 0 से अधिक मात्रा दर्ज करें।',
  );
  static const requestOnHold = TranslatableString(
    en: 'Request put on hold',
    ar: 'تم تعليق الطلب',
    ur: 'درخواست روک دی گئی',
    hi: 'अनुरोध रोका गया',
  );
  static const approvePlanConfirmTitle = TranslatableString(
    en: 'Approve plan?',
    ar: 'الموافقة على الخطة؟',
    ur: 'منصوبہ منظور کریں؟',
    hi: 'योजना अनुमोदित करें?',
  );
  static const approvePlanConfirmBody = TranslatableString(
    en: 'This activates the project and tells procurement to proceed. The approval can\'t be undone here.',
    ar: 'يفعّل هذا المشروع ويُعلم المشتريات بالمتابعة. لا يمكن التراجع عن الموافقة هنا.',
    ur: 'یہ پروجیکٹ کو فعال کرتا ہے اور پروکیورمنٹ کو آگے بڑھنے کا کہتا ہے۔ منظوری یہاں واپس نہیں ہو سکتی۔',
    hi: 'यह प्रोजेक्ट सक्रिय करता है और खरीद को आगे बढ़ने को कहता है। अनुमोदन यहाँ पूर्ववत नहीं हो सकता।',
  );
  static const changesSent = TranslatableString(
    en: 'Changes sent to procurement',
    ar: 'تم إرسال التغييرات إلى المشتريات',
    ur: 'تبدیلیاں پروکیورمنٹ کو بھیج دی گئیں',
    hi: 'बदलाव खरीद को भेजे गए',
  );
  static const comments = TranslatableString(
    en: 'Comments',
    ar: 'التعليقات',
    ur: 'تبصرے',
    hi: 'टिप्पणियाँ',
  );
  static const noCommentsYet = TranslatableString(
    en: 'No comments yet',
    ar: 'لا توجد تعليقات بعد',
    ur: 'ابھی تک کوئی تبصرہ نہیں',
    hi: 'अभी तक कोई टिप्पणी नहीं',
  );
  static const addComment = TranslatableString(
    en: 'Add a comment',
    ar: 'أضف تعليقاً',
    ur: 'تبصرہ شامل کریں',
    hi: 'टिप्पणी जोड़ें',
  );
  static const noComments = TranslatableString(
    en: 'No comments yet',
    ar: 'لا تعليقات بعد',
    ur: 'ابھی کوئی تبصرہ نہیں',
    hi: 'अभी कोई टिप्पणी नहीं',
  );
  static const buildPlan = TranslatableString(
    en: 'Build plan',
    ar: 'إنشاء الخطة',
    ur: 'منصوبہ بنائیں',
    hi: 'योजना बनाएं',
  );
  static const materialPlan = TranslatableString(
    en: 'Material plan',
    ar: 'خطة المواد',
    ur: 'مواد کا منصوبہ',
    hi: 'सामग्री योजना',
  );
  static const buildPlanSubtitle = TranslatableString(
    en: 'List the materials you expect to need. You can edit before submitting.',
    ar: 'اذكر المواد المتوقعة. يمكنك التعديل قبل الإرسال.',
    ur: 'متوقع مواد کی فہرست بنائیں۔ بھیجنے سے پہلے ترمیم کر سکتے ہیں۔',
    hi: 'अपेक्षित सामग्री सूचीबद्ध करें। भेजने से पहले संपादित कर सकते हैं।',
  );
  static const addFromInventory = TranslatableString(
    en: 'Add from inventory',
    ar: 'أضف من المخزون',
    ur: 'انوینٹری سے شامل کریں',
    hi: 'इन्वेंटरी से जोड़ें',
  );
  static const addCustomItem = TranslatableString(
    en: 'Add custom item',
    ar: 'أضف عنصراً مخصصاً',
    ur: 'کسٹم آئٹم شامل کریں',
    hi: 'कस्टम आइटम जोड़ें',
  );
  static const submitToProcurement = TranslatableString(
    en: 'Submit to procurement',
    ar: 'إرسال إلى المشتريات',
    ur: 'پروکیورمنٹ کو بھیجیں',
    hi: 'खरीद को भेजें',
  );
  static const planSubmitted = TranslatableString(
    en: 'Plan submitted to procurement',
    ar: 'تم إرسال الخطة إلى المشتريات',
    ur: 'منصوبہ پروکیورمنٹ کو بھیج دیا گیا',
    hi: 'योजना खरीद को भेजी गई',
  );
  static const emptyPlan = TranslatableString(
    en: 'No items yet',
    ar: 'لا عناصر بعد',
    ur: 'ابھی کوئی آئٹم نہیں',
    hi: 'अभी कोई आइटम नहीं',
  );
  static const emptyPlanHint = TranslatableString(
    en: 'Add materials from inventory or create a custom item.',
    ar: 'أضف مواد من المخزون أو أنشئ عنصراً مخصصاً.',
    ur: 'انوینٹری سے مواد شامل کریں یا کسٹم آئٹم بنائیں۔',
    hi: 'इन्वेंटरी से सामग्री जोड़ें या कस्टम आइटम बनाएं।',
  );
  static const customItem = TranslatableString(
    en: 'Custom item',
    ar: 'عنصر مخصص',
    ur: 'کسٹم آئٹم',
    hi: 'कस्टम आइटम',
  );
  static const description = TranslatableString(
    en: 'Description',
    ar: 'الوصف',
    ur: 'تفصیل',
    hi: 'विवरण',
  );
  static const brand = TranslatableString(
    en: 'Brand',
    ar: 'العلامة التجارية',
    ur: 'برانڈ',
    hi: 'ब्रांड',
  );
  static const countryOfOrigin = TranslatableString(
    en: 'Country of origin',
    ar: 'بلد المنشأ',
    ur: 'ملکِ اصل',
    hi: 'मूल देश',
  );
  static const sizeLabel = TranslatableString(
    en: 'Size',
    ar: 'الحجم',
    ur: 'سائز',
    hi: 'आकार',
  );
  static const ralColour = TranslatableString(
    en: 'RAL colour',
    ar: 'لون RAL',
    ur: 'RAL رنگ',
    hi: 'RAL रंग',
  );
  static const ralColourHint = TranslatableString(
    en: 'Required for grilles, diffusers & dampers',
    ar: 'مطلوب للشبكات والموزعات والمخمدات',
    ur: 'گرلز، ڈفیوزرز اور ڈیمپرز کے لیے ضروری',
    hi: 'ग्रिल, डिफ्यूज़र और डैम्पर हेतु आवश्यक',
  );
  static const addToPlan = TranslatableString(
    en: 'Add to plan',
    ar: 'أضف إلى الخطة',
    ur: 'منصوبے میں شامل کریں',
    hi: 'योजना में जोड़ें',
  );

  // ─── Phase 2 — Receipt & Returns ──────────────────────────
  static const confirmReceipt = TranslatableString(
    en: 'Confirm receipt',
    ar: 'تأكيد الاستلام',
    ur: 'وصولی کی تصدیق',
    hi: 'प्राप्ति की पुष्टि',
  );
  static const confirmReceiptSubtitle = TranslatableString(
    en: 'Confirm exactly what arrived on site. Flag anything short.',
    ar: 'أكد ما وصل إلى الموقع بالضبط. أبلغ عن أي نقص.',
    ur: 'سائٹ پر جو پہنچا اس کی تصدیق کریں۔ کسی بھی کمی کو نشان زد کریں۔',
    hi: 'साइट पर जो पहुंचा उसकी पुष्टि करें। किसी भी कमी को चिह्नित करें।',
  );
  static const dispatchedLabel = TranslatableString(
    en: 'Dispatched',
    ar: 'المُرسَل',
    ur: 'روانہ',
    hi: 'भेजा गया',
  );
  static const receivedLabel = TranslatableString(
    en: 'Received',
    ar: 'المُستلَم',
    ur: 'موصول',
    hi: 'प्राप्त',
  );
  static const shortfallFlagged = TranslatableString(
    en: 'Short — procurement will be notified',
    ar: 'نقص — سيتم إخطار المشتريات',
    ur: 'کمی — پروکیورمنٹ کو مطلع کیا جائے گا',
    hi: 'कमी — खरीद को सूचित किया जाएगा',
  );
  static const receiptConfirmed = TranslatableString(
    en: 'Receipt confirmed',
    ar: 'تم تأكيد الاستلام',
    ur: 'وصولی تصدیق شدہ',
    hi: 'प्राप्ति की पुष्टि हुई',
  );
  static const confirmReceiptQuestion = TranslatableString(
    en: 'Confirm receipt?',
    ar: 'تأكيد الاستلام؟',
    ur: 'وصولی کی تصدیق؟',
    hi: 'प्राप्ति की पुष्टि करें?',
  );
  static const confirmReceiptAllBody = TranslatableString(
    en: 'This records that everything dispatched arrived on site. It updates the request and can\'t be undone here.',
    ar: 'يسجل هذا وصول كل ما تم إرساله إلى الموقع. يحدّث الطلب ولا يمكن التراجع هنا.',
    ur: 'یہ ریکارڈ کرتا ہے کہ روانہ کیا گیا سب کچھ سائٹ پر پہنچ گیا۔ یہ درخواست کو اپڈیٹ کرتا ہے اور یہاں واپس نہیں ہو سکتا۔',
    hi: 'यह दर्ज करता है कि भेजा गया सब कुछ साइट पर पहुँचा। यह अनुरोध अपडेट करता है और यहाँ पूर्ववत नहीं हो सकता।',
  );
  static const confirmReceiptShortBody = TranslatableString(
    en: 'line(s) are short of what was dispatched. Procurement will be notified. Confirm exactly what arrived?',
    ar: 'من البنود ناقصة عمّا تم إرساله. سيتم إخطار المشتريات. تأكيد ما وصل بالضبط؟',
    ur: 'لائن(یں) روانہ کی گئی مقدار سے کم ہیں۔ پروکیورمنٹ کو مطلع کیا جائے گا۔ جو پہنچا اس کی تصدیق کریں؟',
    hi: 'लाइन(ें) भेजी गई मात्रा से कम हैं। खरीद को सूचित किया जाएगा। जो पहुँचा उसकी पुष्टि करें?',
  );
  static const returnToStore = TranslatableString(
    en: 'Return to store',
    ar: 'الإرجاع إلى المخزن',
    ur: 'اسٹور واپسی',
    hi: 'स्टोर वापसी',
  );
  static const returnMaterial = TranslatableString(
    en: 'Return material',
    ar: 'إرجاع المواد',
    ur: 'مواد واپس کریں',
    hi: 'सामग्री लौटाएं',
  );
  static const returnSubtitle = TranslatableString(
    en: 'Send surplus, wrong, or damaged material back to store.',
    ar: 'أعد المواد الفائضة أو الخاطئة أو التالفة إلى المخزن.',
    ur: 'فاضل، غلط یا خراب مواد اسٹور واپس بھیجیں۔',
    hi: 'अधिशेष, गलत या क्षतिग्रस्त सामग्री स्टोर वापस भेजें।',
  );
  static const reason = TranslatableString(
    en: 'Reason',
    ar: 'السبب',
    ur: 'وجہ',
    hi: 'कारण',
  );
  static const submitReturn = TranslatableString(
    en: 'Submit return',
    ar: 'إرسال الإرجاع',
    ur: 'واپسی جمع کریں',
    hi: 'वापसी सबमिट करें',
  );
  static const returnSubmitted = TranslatableString(
    en: 'Return submitted — procurement will confirm and restock',
    ar: 'تم إرسال الإرجاع — ستؤكد المشتريات وتعيد التخزين',
    ur: 'واپسی جمع — پروکیورمنٹ تصدیق کر کے دوبارہ اسٹاک کرے گا',
    hi: 'वापसी सबमिट — खरीद पुष्टि कर पुनः स्टॉक करेगी',
  );
  static const addItemToReturn = TranslatableString(
    en: 'Add item to return',
    ar: 'أضف عنصراً للإرجاع',
    ur: 'واپسی کے لیے آئٹم شامل کریں',
    hi: 'वापसी हेतु आइटम जोड़ें',
  );
  static const addAtLeastOneReturnItem = TranslatableString(
    en: 'Add at least one item to return first',
    ar: 'أضف عنصراً واحداً على الأقل للإرجاع أولاً',
    ur: 'پہلے واپسی کے لیے کم از کم ایک آئٹم شامل کریں',
    hi: 'पहले वापसी हेतु कम से कम एक आइटम जोड़ें',
  );
  static const returnSubmitHint = TranslatableString(
    en: 'Procurement will confirm and restock once you submit.',
    ar: 'ستؤكد المشتريات وتعيد التخزين بعد الإرسال.',
    ur: 'جمع کرانے پر پروکیورمنٹ تصدیق کر کے دوبارہ اسٹاک کرے گا۔',
    hi: 'सबमिट करने पर खरीद पुष्टि कर पुनः स्टॉक करेगी।',
  );
  static const submitReturnConfirm = TranslatableString(
    en: 'Submit return?',
    ar: 'إرسال الإرجاع؟',
    ur: 'واپسی جمع کریں؟',
    hi: 'वापसी सबमिट करें?',
  );
  static const submitReturnConfirmBody = TranslatableString(
    en: 'This sends the return to procurement to confirm and restock. Check the quantities match what you\'re sending back.',
    ar: 'يرسل هذا الإرجاع إلى المشتريات للتأكيد وإعادة التخزين. تأكد من تطابق الكميات مع ما تعيده.',
    ur: 'یہ واپسی پروکیورمنٹ کو تصدیق اور دوبارہ اسٹاک کے لیے بھیجتا ہے۔ یقینی بنائیں کہ مقدار آپ کی واپس کی جانے والی چیزوں سے مطابقت رکھتی ہے۔',
    hi: 'यह वापसी खरीद को पुष्टि व पुनः स्टॉक हेतु भेजता है। जांचें कि मात्रा आपकी लौटाई जा रही वस्तुओं से मेल खाती है।',
  );
  static const editQuantity = TranslatableString(
    en: 'Edit quantity',
    ar: 'تعديل الكمية',
    ur: 'مقدار میں ترمیم',
    hi: 'मात्रा संपादित करें',
  );

  // ─── Plan diff / re-approval ──────────────────────────────
  static const editPlan = TranslatableString(
    en: 'Edit plan',
    ar: 'تعديل الخطة',
    ur: 'منصوبہ ترمیم کریں',
    hi: 'योजना संपादित करें',
  );
  static const viewChanges = TranslatableString(
    en: 'View changes',
    ar: 'عرض التغييرات',
    ur: 'تبدیلیاں دیکھیں',
    hi: 'बदलाव देखें',
  );
  static const whatChanged = TranslatableString(
    en: 'What changed',
    ar: 'ما الذي تغيّر',
    ur: 'کیا تبدیل ہوا',
    hi: 'क्या बदला',
  );
  static const changesAwaitingReview = TranslatableString(
    en: 'Edited — awaiting procurement re-review',
    ar: 'معدّل — بانتظار إعادة المراجعة',
    ur: 'ترمیم شدہ — دوبارہ جائزے کا انتظار',
    hi: 'संपादित — पुनः समीक्षा प्रतीक्षित',
  );
  static const diffAdded = TranslatableString(
    en: 'Added',
    ar: 'مضاف',
    ur: 'شامل',
    hi: 'जोड़ा',
  );
  static const diffRemoved = TranslatableString(
    en: 'Removed',
    ar: 'محذوف',
    ur: 'حذف شدہ',
    hi: 'हटाया',
  );
  static const diffChanged = TranslatableString(
    en: 'Changed',
    ar: 'معدّل',
    ur: 'تبدیل شدہ',
    hi: 'बदला',
  );
  static const noChanges = TranslatableString(
    en: 'No changes',
    ar: 'لا تغييرات',
    ur: 'کوئی تبدیلی نہیں',
    hi: 'कोई बदलाव नहीं',
  );
  static const unchangedUnaffected = TranslatableString(
    en: 'unchanged items stay approved',
    ar: 'بنود لم تتغير تبقى معتمدة',
    ur: 'غیر تبدیل شدہ اشیاء منظور رہیں گی',
    hi: 'अपरिवर्तित आइटम स्वीकृत रहते हैं',
  );

  // ─── Attendance / Employee (HR) ───────────────────────────
  static const myData = TranslatableString(
    en: 'My data',
    ar: 'بياناتي',
    ur: 'میرا ڈیٹا',
    hi: 'मेरा डेटा',
  );
  static const showMore = TranslatableString(
    en: 'Show more',
    ar: 'عرض المزيد',
    ur: 'مزید دیکھیں',
    hi: 'और देखें',
  );
  static const myProfile = TranslatableString(
    en: 'My profile',
    ar: 'ملفي الشخصي',
    ur: 'میرا پروفائل',
    hi: 'मेरी प्रोफ़ाइल',
  );
  static const attendanceSection = TranslatableString(
    en: 'Attendance',
    ar: 'الدخول والخروج',
    ur: 'حاضری',
    hi: 'उपस्थिति',
  );
  static const checkInLabel = TranslatableString(
    en: 'Check-in',
    ar: 'حضور',
    ur: 'حاضری',
    hi: 'चेक-इन',
  );
  static const checkOutLabel = TranslatableString(
    en: 'Check-out',
    ar: 'انصراف',
    ur: 'روانگی',
    hi: 'चेक-आउट',
  );
  static const remainingLabel = TranslatableString(
    en: 'Remaining',
    ar: 'المتبقي',
    ur: 'باقی',
    hi: 'शेष',
  );
  static const hoursUnit = TranslatableString(
    en: 'hours',
    ar: 'ساعات',
    ur: 'گھنٹے',
    hi: 'घंटे',
  );
  static const requestPermission = TranslatableString(
    en: 'Request permission',
    ar: 'طلب استئذان',
    ur: 'اجازت طلب کریں',
    hi: 'अनुमति मांगें',
  );
  static const leavesSection = TranslatableString(
    en: 'Leaves',
    ar: 'الاجازات',
    ur: 'چھٹیاں',
    hi: 'छुट्टियाँ',
  );
  static const requestLeave = TranslatableString(
    en: 'Request leave',
    ar: 'طلب اجازة',
    ur: 'چھٹی کی درخواست',
    hi: 'छुट्टी का अनुरोध',
  );
  static const daysUnit = TranslatableString(
    en: 'days',
    ar: 'أيام',
    ur: 'دن',
    hi: 'दिन',
  );
  static const employmentSection = TranslatableString(
    en: 'Employment',
    ar: 'بيانات التوظيف',
    ur: 'ملازمت کی تفصیلات',
    hi: 'रोज़गार विवरण',
  );
  static const quickLinksSection = TranslatableString(
    en: 'Quick links',
    ar: 'روابط سريعة',
    ur: 'فوری لنکس',
    hi: 'त्वरित लिंक',
  );
  static const roleLabel = TranslatableString(
    en: 'Role',
    ar: 'الوظيفة',
    ur: 'عہدہ',
    hi: 'भूमिका',
  );
  static const employeeIdLabel = TranslatableString(
    en: 'Employee ID',
    ar: 'الرقم الوظيفي',
    ur: 'ملازم آئی ڈی',
    hi: 'कर्मचारी आईडी',
  );
  static const departmentLabel = TranslatableString(
    en: 'Department',
    ar: 'الإدارة',
    ur: 'شعبہ',
    hi: 'विभाग',
  );
  static const todayLabel = TranslatableString(
    en: 'Today',
    ar: 'اليوم',
    ur: 'آج',
    hi: 'आज',
  );
  static const notMarkedYet = TranslatableString(
    en: 'Not marked',
    ar: 'غير مسجل',
    ur: 'درج نہیں',
    hi: 'दर्ज नहीं',
  );
  static const annualLeftLabel = TranslatableString(
    en: 'Annual left',
    ar: 'المتبقي السنوي',
    ur: 'سالانہ باقی',
    hi: 'वार्षिक शेष',
  );
  static const pendingLabel = TranslatableString(
    en: 'Pending',
    ar: 'قيد الانتظار',
    ur: 'زیر التوا',
    hi: 'लंबित',
  );
  static const nationalityLabel = TranslatableString(
    en: 'Nationality',
    ar: 'الجنسية',
    ur: 'قومیت',
    hi: 'राष्ट्रीयता',
  );
  static const joinedLabel = TranslatableString(
    en: 'Joined',
    ar: 'تاريخ الالتحاق',
    ur: 'شمولیت',
    hi: 'शामिल हुए',
  );
  static const tenureLabelText = TranslatableString(
    en: 'Tenure',
    ar: 'مدة الخدمة',
    ur: 'مدت ملازمت',
    hi: 'सेवा अवधि',
  );

  // ─── Leave management ──────────────────────────────────────────
  static const myLeave = TranslatableString(
    en: 'My Leave',
    ar: 'إجازتي',
    ur: 'میری چھٹیاں',
    hi: 'मेरी छुट्टी',
  );
  static const leaveRequestsTitle = TranslatableString(
    en: 'Leave Requests',
    ar: 'طلبات الإجازة',
    ur: 'چھٹی کی درخواستیں',
    hi: 'छुट्टी के अनुरोध',
  );
  static const leaveRequestsHint = TranslatableString(
    en: 'Approve or reject leave',
    ar: 'الموافقة على الإجازة أو رفضها',
    ur: 'چھٹی منظور یا مسترد کریں',
    hi: 'छुट्टी स्वीकृत या अस्वीकृत करें',
  );
  static const leaveBalance = TranslatableString(
    en: 'Leave Balance',
    ar: 'رصيد الإجازات',
    ur: 'چھٹیوں کا بیلنس',
    hi: 'छुट्टी शेष',
  );
  static const leaveTypeLabel = TranslatableString(
    en: 'Leave Type',
    ar: 'نوع الإجازة',
    ur: 'چھٹی کی قسم',
    hi: 'छुट्टी का प्रकार',
  );
  static const leaveEndDate = TranslatableString(
    en: 'End Date',
    ar: 'تاريخ الانتهاء',
    ur: 'اختتامی تاریخ',
    hi: 'समाप्ति तिथि',
  );
  static const reasonOptional = TranslatableString(
    en: 'Reason (optional)',
    ar: 'السبب (اختياري)',
    ur: 'وجہ (اختیاری)',
    hi: 'कारण (वैकल्पिक)',
  );
  static const approveAction = TranslatableString(
    en: 'Approve',
    ar: 'موافقة',
    ur: 'منظور',
    hi: 'स्वीकृत',
  );
  static const rejectAction = TranslatableString(
    en: 'Reject',
    ar: 'رفض',
    ur: 'مسترد',
    hi: 'अस्वीकृत',
  );
  static const withdrawAction = TranslatableString(
    en: 'Withdraw',
    ar: 'سحب',
    ur: 'واپس لیں',
    hi: 'वापस लें',
  );
  static const withdrawConfirmTitle = TranslatableString(
    en: 'Withdraw request?',
    ar: 'سحب الطلب؟',
    ur: 'درخواست واپس لیں؟',
    hi: 'अनुरोध वापस लें?',
  );
  static const withdrawConfirmBody = TranslatableString(
    en: 'This cancels your pending leave request. You can file a new one anytime.',
    ar: 'يلغي هذا طلب إجازتك المعلق. يمكنك تقديم طلب جديد في أي وقت.',
    ur: 'یہ آپ کی زیر التوا چھٹی کی درخواست منسوخ کر دے گا۔ آپ کبھی بھی نئی درخواست دے سکتے ہیں۔',
    hi: 'यह आपका लंबित छुट्टी अनुरोध रद्द करता है। आप कभी भी नया दे सकते हैं।',
  );
  static const overBalanceWarning = TranslatableString(
    en: 'Exceeds the remaining annual balance',
    ar: 'يتجاوز الرصيد السنوي المتبقي',
    ur: 'سالانہ باقی بیلنس سے زیادہ ہے',
    hi: 'वार्षिक शेष से अधिक है',
  );
  static const leaveOverlapWarning = TranslatableString(
    en: 'Overlaps an existing leave',
    ar: 'يتداخل مع إجازة قائمة',
    ur: 'موجودہ چھٹی سے ٹکراؤ ہے',
    hi: 'मौजूदा छुट्टी से टकराव',
  );
  static const pickStartEndDate = TranslatableString(
    en: 'Pick a start and end date',
    ar: 'اختر تاريخ البدء والانتهاء',
    ur: 'آغاز اور اختتام کی تاریخ منتخب کریں',
    hi: 'आरंभ और समाप्ति तिथि चुनें',
  );
  static const endAfterStart = TranslatableString(
    en: 'End date must be on or after the start date',
    ar: 'يجب أن يكون تاريخ الانتهاء في أو بعد تاريخ البدء',
    ur: 'اختتامی تاریخ آغاز کی تاریخ پر یا اس کے بعد ہونی چاہیے',
    hi: 'समाप्ति तिथि आरंभ तिथि पर या बाद में होनी चाहिए',
  );
  static const notLinkedToEmployee = TranslatableString(
    en: 'Your account isn\'t linked to an employee record yet — contact your admin.',
    ar: 'حسابك غير مرتبط بسجل موظف بعد — تواصل مع المسؤول.',
    ur: 'آپ کا اکاؤنٹ ابھی ملازم ریکارڈ سے منسلک نہیں — ایڈمن سے رابطہ کریں۔',
    hi: 'आपका खाता अभी कर्मचारी रिकॉर्ड से लिंक नहीं है — एडमिन से संपर्क करें।',
  );
  static const leaveSubmitted = TranslatableString(
    en: 'Leave request submitted',
    ar: 'تم إرسال طلب الإجازة',
    ur: 'چھٹی کی درخواست جمع ہو گئی',
    hi: 'छुट्टी अनुरोध सबमिट हुआ',
  );
  static const leaveApprovedMsg = TranslatableString(
    en: 'Leave approved',
    ar: 'تمت الموافقة على الإجازة',
    ur: 'چھٹی منظور ہو گئی',
    hi: 'छुट्टी स्वीकृत',
  );
  static const leaveRejectedMsg = TranslatableString(
    en: 'Leave rejected',
    ar: 'تم رفض الإجازة',
    ur: 'چھٹی مسترد ہو گئی',
    hi: 'छुट्टी अस्वीकृत',
  );
  static const noLeaveRequests = TranslatableString(
    en: 'No leave requests yet',
    ar: 'لا توجد طلبات إجازة بعد',
    ur: 'ابھی کوئی چھٹی کی درخواست نہیں',
    hi: 'अभी कोई छुट्टी अनुरोध नहीं',
  );
  static const noPendingLeave = TranslatableString(
    en: 'No pending requests',
    ar: 'لا توجد طلبات معلقة',
    ur: 'کوئی زیر التواء درخواست نہیں',
    hi: 'कोई लंबित अनुरोध नहीं',
  );
}

/// A translatable string with all supported language variants.
class TranslatableString {
  const TranslatableString({
    required this.en,
    required this.ar,
    required this.ur,
    required this.hi,
  });

  final String en;
  final String ar;
  final String ur;
  final String hi;

  /// English primary text.
  String get primary => en;

  /// Text for the one language currently visible in the workspace.
  String active(AppLanguage lang) {
    if (lang == AppLanguage.english) return primary;
    return secondary(lang);
  }

  /// Translation for the configured non-English language.
  ///
  /// Kept as a compatibility API for existing call sites. New UI should use
  /// [active] so it renders exactly one language.
  String secondary(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.english:
      case AppLanguage.arabic:
        return ar;
      case AppLanguage.urdu:
        return ur;
      case AppLanguage.hindi:
        return hi;
    }
  }
}
