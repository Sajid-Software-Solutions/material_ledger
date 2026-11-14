import 'app_strings.dart';

/// Copy for the role-based Overview (`YORKS_V1_ROLE_OVERVIEW_V2`).
///
/// Placeholders in braces (`{n}`, `{name}`, `{date}` …) are replaced by the
/// builders. Every figure behind this copy comes from a protected,
/// non-commercial server projection.
abstract final class YorksV1RoleOverviewStrings {
  // ─── Page chrome ────────────────────────────────────────────────────────
  static const overview = TranslatableString(
    en: 'Overview',
    ar: 'نظرة عامة',
    ur: 'جائزہ',
    hi: 'अवलोकन',
  );
  static const goodDay = TranslatableString(
    en: 'Welcome back',
    ar: 'مرحبًا بعودتك',
    ur: 'خوش آمدید',
    hi: 'फिर से स्वागत है',
  );
  static const refresh = TranslatableString(
    en: 'Refresh',
    ar: 'تحديث',
    ur: 'تازہ کریں',
    hi: 'रीफ़्रेश करें',
  );
  static const checkingServer = TranslatableString(
    en: 'Checking with the server…',
    ar: 'جارٍ التحقق من الخادم…',
    ur: 'سرور سے تصدیق ہو رہی ہے…',
    hi: 'सर्वर से जाँच हो रही है…',
  );
  static const updatedAt = TranslatableString(
    en: 'Updated {time} · server-confirmed',
    ar: 'آخر تحديث {time} · مؤكد من الخادم',
    ur: 'اپڈیٹ {time} · سرور سے تصدیق شدہ',
    hi: 'अपडेट {time} · सर्वर-पुष्ट',
  );
  static const couldNotLoad = TranslatableString(
    en: 'This card could not be loaded. Nothing has been changed.',
    ar: 'تعذر تحميل هذه البطاقة. لم يتم تغيير أي شيء.',
    ur: 'یہ کارڈ لوڈ نہیں ہو سکا۔ کچھ بھی تبدیل نہیں ہوا۔',
    hi: 'यह कार्ड लोड नहीं हो सका। कुछ भी नहीं बदला गया।',
  );
  static const couldNotLoadShort = TranslatableString(
    en: 'Could not load · nothing changed',
    ar: 'تعذر التحميل · لم يتغير شيء',
    ur: 'لوڈ نہیں ہو سکا · کچھ نہیں بدلا',
    hi: 'लोड नहीं हुआ · कुछ नहीं बदला',
  );
  static const recentOpenRequestsOnly = TranslatableString(
    en: 'Based on the 100 most recently updated open requests.',
    ar: 'استنادًا إلى أحدث 100 طلب مفتوح تم تحديثه.',
    ur: 'حال ہی میں اپڈیٹ ہونے والی 100 کھلی ریکویسٹس کی بنیاد پر۔',
    hi: 'हाल में अपडेट हुई 100 खुली रिक्वेस्ट के आधार पर।',
  );
  static const retry = TranslatableString(
    en: 'Retry',
    ar: 'إعادة المحاولة',
    ur: 'دوبارہ کوشش کریں',
    hi: 'फिर से कोशिश करें',
  );
  static const waiting = TranslatableString(
    en: 'waiting',
    ar: 'انتظار',
    ur: 'منتظر',
    hi: 'प्रतीक्षा',
  );
  static const showAll = TranslatableString(
    en: 'Show all {count}',
    ar: 'عرض الكل ({count})',
    ur: 'تمام {count} دکھائیں',
    hi: 'सभी {count} दिखाएँ',
  );
  static const openAll = TranslatableString(
    en: 'Open all {count} in Material Requests',
    ar: 'فتح الكل ({count}) في طلبات المواد',
    ur: 'تمام {count} میٹریل ریکویسٹس میں کھولیں',
    hi: 'सभी {count} मटेरियल रिक्वेस्ट में खोलें',
  );
  static const viewAll = TranslatableString(
    en: 'View all',
    ar: 'عرض الكل',
    ur: 'سب دیکھیں',
    hi: 'सभी देखें',
  );
  static const nothingWaiting = TranslatableString(
    en: 'Nothing waiting',
    ar: 'لا شيء بالانتظار',
    ur: 'کچھ زیر التوا نہیں',
    hi: 'कुछ भी लंबित नहीं',
  );
  static const readOnly = TranslatableString(
    en: 'Read only',
    ar: 'للقراءة فقط',
    ur: 'صرف دیکھنے کے لیے',
    hi: 'केवल पढ़ने के लिए',
  );
  static const orgWide = TranslatableString(
    en: 'Organisation-wide',
    ar: 'على مستوى المؤسسة',
    ur: 'پوری تنظیم',
    hi: 'पूरे संगठन में',
  );
  static const assignedProjects = TranslatableString(
    en: 'Assigned projects',
    ar: 'المشاريع المسندة',
    ur: 'تفویض کردہ پروجیکٹس',
    hi: 'सौंपे गए प्रोजेक्ट',
  );
  static const oneAssignedProject = TranslatableString(
    en: '1 assigned project',
    ar: 'مشروع مسند واحد',
    ur: '1 تفویض کردہ پروجیکٹ',
    hi: '1 सौंपा गया प्रोजेक्ट',
  );
  static const assignedProjectsCount = TranslatableString(
    en: '{n} assigned projects',
    ar: '{n} مشاريع مسندة',
    ur: '{n} تفویض کردہ پروجیکٹس',
    hi: '{n} सौंपे गए प्रोजेक्ट',
  );

  // ─── Units and dates ────────────────────────────────────────────────────
  static const underAnHour = TranslatableString(
    en: '< 1 h',
    ar: '< 1 س',
    ur: '< 1 گھنٹہ',
    hi: '< 1 घं',
  );
  static const hoursShort = TranslatableString(
    en: '{n} h',
    ar: '{n} س',
    ur: '{n} گھنٹے',
    hi: '{n} घं',
  );
  static const daysShort = TranslatableString(
    en: '{n} d',
    ar: '{n} ي',
    ur: '{n} دن',
    hi: '{n} दिन',
  );
  static const hoursDecimal = TranslatableString(
    en: '{n} hours',
    ar: '{n} ساعة',
    ur: '{n} گھنٹے',
    hi: '{n} घंटे',
  );
  static const daysDecimal = TranslatableString(
    en: '{n} days',
    ar: '{n} يوم',
    ur: '{n} دن',
    hi: '{n} दिन',
  );
  static const today = TranslatableString(
    en: 'today',
    ar: 'اليوم',
    ur: 'آج',
    hi: 'आज',
  );
  static const tomorrow = TranslatableString(
    en: 'tomorrow',
    ar: 'غدًا',
    ur: 'کل',
    hi: 'कल',
  );
  static const inDays = TranslatableString(
    en: 'in {n} days',
    ar: 'خلال {n} أيام',
    ur: '{n} دن میں',
    hi: '{n} दिन में',
  );
  static const overdueDays = TranslatableString(
    en: 'Overdue {n} d',
    ar: 'متأخر {n} ي',
    ur: '{n} دن تاخیر',
    hi: '{n} दिन विलंब',
  );
  static const neededOn = TranslatableString(
    en: 'Needed {date}',
    ar: 'مطلوب {date}',
    ur: 'درکار {date}',
    hi: 'आवश्यक {date}',
  );
  static const sinceDate = TranslatableString(
    en: 'Since {date}',
    ar: 'منذ {date}',
    ur: '{date} سے',
    hi: '{date} से',
  );
  static const oneLine = TranslatableString(
    en: '1 line',
    ar: 'بند واحد',
    ur: '1 لائن',
    hi: '1 लाइन',
  );
  static const lines = TranslatableString(
    en: '{n} lines',
    ar: '{n} بنود',
    ur: '{n} لائنیں',
    hi: '{n} लाइनें',
  );
  static const unitsCount = TranslatableString(
    en: '{n} units',
    ar: '{n} وحدة',
    ur: '{n} یونٹس',
    hi: '{n} यूनिट',
  );
  static const oneBuilding = TranslatableString(
    en: '1 building + Common',
    ar: 'مبنى واحد + المشترك',
    ur: '1 عمارت + مشترکہ',
    hi: '1 भवन + कॉमन',
  );
  static const buildingsCount = TranslatableString(
    en: '{n} buildings + Common',
    ar: '{n} مبانٍ + المشترك',
    ur: '{n} عمارتیں + مشترکہ',
    hi: '{n} भवन + कॉमन',
  );
  static const oldest = TranslatableString(
    en: 'Oldest {age}',
    ar: 'الأقدم {age}',
    ur: 'سب سے پرانا {age}',
    hi: 'सबसे पुराना {age}',
  );
  static const urgentCount = TranslatableString(
    en: '{n} urgent',
    ar: '{n} عاجل',
    ur: '{n} فوری',
    hi: '{n} तत्काल',
  );
  static const plusMore = TranslatableString(
    en: '+{n} more',
    ar: '+{n} أخرى',
    ur: '+{n} مزید',
    hi: '+{n} और',
  );
  static const outOfStockCount = TranslatableString(
    en: '{n} out of stock',
    ar: '{n} نفد من المخزون',
    ur: '{n} اسٹاک ختم',
    hi: '{n} स्टॉक समाप्त',
  );
  static const onHoldAndTotal = TranslatableString(
    en: '{hold} on hold · {total} in total',
    ar: '{hold} معلقة · {total} إجمالًا',
    ur: '{hold} روکے گئے · کل {total}',
    hi: '{hold} रुके हुए · कुल {total}',
  );
  static const waitingApprovalOrArrangement = TranslatableString(
    en: '{n} waiting for approval or arrangement',
    ar: '{n} بانتظار الموافقة أو الترتيب',
    ur: '{n} منظوری یا انتظام کے منتظر',
    hi: '{n} स्वीकृति या व्यवस्था की प्रतीक्षा में',
  );
  static const totalRequestsSub = TranslatableString(
    en: '{n} requests, including completed ones. Select a stage to open the register.',
    ar: '{n} طلبًا، بما في ذلك المكتملة. اختر مرحلة لفتح السجل.',
    ur: '{n} ریکویسٹس، مکمل شدہ سمیت۔ رجسٹر کھولنے کے لیے مرحلہ منتخب کریں۔',
    hi: '{n} रिक्वेस्ट, पूर्ण सहित। रजिस्टर खोलने के लिए चरण चुनें।',
  );
  static const teamCounts = TranslatableString(
    en: '{pe} PE · {se} SE',
    ar: '{pe} مهندس مشروع · {se} مهندس موقع',
    ur: '{pe} PE · {se} SE',
    hi: '{pe} PE · {se} SE',
  );

  // ─── Request copy ───────────────────────────────────────────────────────
  static const draft = TranslatableString(
    en: 'Draft',
    ar: 'مسودة',
    ur: 'ڈرافٹ',
    hi: 'ड्राफ्ट',
  );
  static const untitledDraft = TranslatableString(
    en: 'Untitled draft',
    ar: 'مسودة بلا عنوان',
    ur: 'بغیر عنوان ڈرافٹ',
    hi: 'बिना शीर्षक ड्राफ्ट',
  );
  static const savedToAccount = TranslatableString(
    en: 'Saved to your account {when}',
    ar: 'محفوظة في حسابك {when}',
    ur: 'آپ کے اکاؤنٹ میں محفوظ {when}',
    hi: 'आपके खाते में सहेजा गया {when}',
  );
  static const submittedBy = TranslatableString(
    en: 'Submitted by {name}',
    ar: 'قدّمه {name}',
    ur: '{name} نے جمع کرایا',
    hi: '{name} द्वारा जमा',
  );
  static const submittedByRole = TranslatableString(
    en: 'Submitted by {name} · {role}',
    ar: 'قدّمه {name} · {role}',
    ur: '{name} نے جمع کرایا · {role}',
    hi: '{name} द्वारा जमा · {role}',
  );
  static const urgent = TranslatableString(
    en: 'Urgent',
    ar: 'عاجل',
    ur: 'فوری',
    hi: 'तत्काल',
  );
  static const requiredDatePassed = TranslatableString(
    en: 'Required date passed',
    ar: 'تجاوز التاريخ المطلوب',
    ur: 'مطلوبہ تاریخ گزر گئی',
    hi: 'आवश्यक तिथि निकल गई',
  );
  static const exception = TranslatableString(
    en: 'Exception',
    ar: 'استثناء',
    ur: 'استثنا',
    hi: 'अपवाद',
  );
  static const youNextStep = TranslatableString(
    en: 'You — next step',
    ar: 'أنت — الخطوة التالية',
    ur: 'آپ — اگلا قدم',
    hi: 'आप — अगला कदम',
  );
  static const approveRequest = TranslatableString(
    en: 'Approve request',
    ar: 'اعتماد الطلب',
    ur: 'ریکویسٹ منظور کریں',
    hi: 'रिक्वेस्ट स्वीकृत करें',
  );
  static const approveArrangement = TranslatableString(
    en: 'Approve arrangement',
    ar: 'اعتماد الترتيب',
    ur: 'انتظام منظور کریں',
    hi: 'व्यवस्था स्वीकृत करें',
  );
  static const arrangeRequest = TranslatableString(
    en: 'Arrange request',
    ar: 'ترتيب الطلب',
    ur: 'ریکویسٹ کا انتظام کریں',
    hi: 'रिक्वेस्ट की व्यवस्था करें',
  );
  static const dispatchRequest = TranslatableString(
    en: 'Dispatch',
    ar: 'إرسال',
    ur: 'روانہ کریں',
    hi: 'डिस्पैच करें',
  );
  static const dispatchReplacement = TranslatableString(
    en: 'Dispatch replacement',
    ar: 'إرسال البديل',
    ur: 'متبادل روانہ کریں',
    hi: 'प्रतिस्थापन डिस्पैच करें',
  );
  static const confirmReceipt = TranslatableString(
    en: 'Confirm receipt',
    ar: 'تأكيد الاستلام',
    ur: 'وصولی کی تصدیق کریں',
    hi: 'प्राप्ति की पुष्टि करें',
  );
  static const closeRequest = TranslatableString(
    en: 'Close request',
    ar: 'إغلاق الطلب',
    ur: 'ریکویسٹ بند کریں',
    hi: 'रिक्वेस्ट बंद करें',
  );
  static const updateReturnedRequest = TranslatableString(
    en: 'Update returned request',
    ar: 'تحديث الطلب المعاد',
    ur: 'واپس کی گئی ریکویسٹ اپڈیٹ کریں',
    hi: 'लौटाई गई रिक्वेस्ट अपडेट करें',
  );
  static const review = TranslatableString(
    en: 'Review',
    ar: 'مراجعة',
    ur: 'جائزہ لیں',
    hi: 'समीक्षा करें',
  );
  static const arrange = TranslatableString(
    en: 'Arrange',
    ar: 'ترتيب',
    ur: 'انتظام کریں',
    hi: 'व्यवस्था करें',
  );
  static const dispatch = TranslatableString(
    en: 'Dispatch',
    ar: 'إرسال',
    ur: 'روانہ کریں',
    hi: 'डिस्पैच',
  );
  static const reviewReceipt = TranslatableString(
    en: 'Review receipt',
    ar: 'مراجعة الاستلام',
    ur: 'وصولی کا جائزہ',
    hi: 'प्राप्ति की समीक्षा',
  );
  static const close = TranslatableString(
    en: 'Close',
    ar: 'إغلاق',
    ur: 'بند کریں',
    hi: 'बंद करें',
  );
  static const editRequest = TranslatableString(
    en: 'Edit request',
    ar: 'تعديل الطلب',
    ur: 'ریکویسٹ میں ترمیم',
    hi: 'रिक्वेस्ट संपादित करें',
  );
  static const continueDraft = TranslatableString(
    en: 'Continue',
    ar: 'متابعة',
    ur: 'جاری رکھیں',
    hi: 'जारी रखें',
  );
  static const open = TranslatableString(
    en: 'Open',
    ar: 'فتح',
    ur: 'کھولیں',
    hi: 'खोलें',
  );

  // ─── Actions ────────────────────────────────────────────────────────────
  static const newMaterialRequest = TranslatableString(
    en: 'New Material Request',
    ar: 'طلب مواد جديد',
    ur: 'نئی میٹریل ریکویسٹ',
    hi: 'नई मटेरियल रिक्वेस्ट',
  );
  static const newProject = TranslatableString(
    en: 'New Project',
    ar: 'مشروع جديد',
    ur: 'نیا پروجیکٹ',
    hi: 'नया प्रोजेक्ट',
  );
  static const createReturn = TranslatableString(
    en: 'Create return',
    ar: 'إنشاء مرتجع',
    ur: 'واپسی بنائیں',
    hi: 'वापसी बनाएँ',
  );
  static const openRequestsAction = TranslatableString(
    en: 'Open Material Requests',
    ar: 'فتح طلبات المواد',
    ur: 'میٹریل ریکویسٹس کھولیں',
    hi: 'मटेरियल रिक्वेस्ट खोलें',
  );
  static const browseInventory = TranslatableString(
    en: 'Browse / Inventory',
    ar: 'تصفح / المخزون',
    ur: 'براؤز / انوینٹری',
    hi: 'ब्राउज़ / इन्वेंटरी',
  );
  static const dispatches = TranslatableString(
    en: 'Dispatches',
    ar: 'الإرساليات',
    ur: 'روانگیاں',
    hi: 'डिस्पैच',
  );
  static const reviewApprovals = TranslatableString(
    en: 'Review approvals',
    ar: 'مراجعة الموافقات',
    ur: 'منظوریوں کا جائزہ',
    hi: 'स्वीकृतियों की समीक्षा',
  );
  static const userManagement = TranslatableString(
    en: 'User Management',
    ar: 'إدارة المستخدمين',
    ur: 'یوزر مینجمنٹ',
    hi: 'उपयोगकर्ता प्रबंधन',
  );
  static const projects = TranslatableString(
    en: 'Projects',
    ar: 'المشاريع',
    ur: 'پروجیکٹس',
    hi: 'प्रोजेक्ट',
  );
  static const materialRequests = TranslatableString(
    en: 'Material Requests',
    ar: 'طلبات المواد',
    ur: 'میٹریل ریکویسٹس',
    hi: 'मटेरियल रिक्वेस्ट',
  );
  static const viewAllRequests = TranslatableString(
    en: 'View All Requests',
    ar: 'عرض كل الطلبات',
    ur: 'تمام ریکویسٹس دیکھیں',
    hi: 'सभी रिक्वेस्ट देखें',
  );
  static const allProjects = TranslatableString(
    en: 'All projects',
    ar: 'كل المشاريع',
    ur: 'تمام پروجیکٹس',
    hi: 'सभी प्रोजेक्ट',
  );
  static const allMyRequests = TranslatableString(
    en: 'All my requests',
    ar: 'كل طلباتي',
    ur: 'میری تمام ریکویسٹس',
    hi: 'मेरी सभी रिक्वेस्ट',
  );
  static const openInventory = TranslatableString(
    en: 'Open inventory',
    ar: 'فتح المخزون',
    ur: 'انوینٹری کھولیں',
    hi: 'इन्वेंटरी खोलें',
  );
  static const assign = TranslatableString(
    en: 'Assign',
    ar: 'إسناد',
    ur: 'تفویض کریں',
    hi: 'सौंपें',
  );
  static const ductSizer = TranslatableString(
    en: 'Duct Sizer',
    ar: 'حاسبة مقاس الدكت',
    ur: 'ڈکٹ سائزر',
    hi: 'डक्ट साइज़र',
  );
  static const ductSizerSub = TranslatableString(
    en: 'Size ducts on site',
    ar: 'تحديد مقاس الدكت في الموقع',
    ur: 'سائٹ پر ڈکٹ کا سائز',
    hi: 'साइट पर डक्ट का आकार',
  );
  static const espCalculator = TranslatableString(
    en: 'ESP Calculator',
    ar: 'حاسبة الضغط الساكن',
    ur: 'ESP کیلکولیٹر',
    hi: 'ESP कैलकुलेटर',
  );
  static const espCalculatorSub = TranslatableString(
    en: 'Fan static pressure',
    ar: 'الضغط الساكن للمروحة',
    ur: 'پنکھے کا اسٹیٹک پریشر',
    hi: 'फैन स्टैटिक प्रेशर',
  );
  static const siteTools = TranslatableString(
    en: 'Site tools',
    ar: 'أدوات الموقع',
    ur: 'سائٹ ٹولز',
    hi: 'साइट टूल',
  );
  static const engineeringTools = TranslatableString(
    en: 'Engineering tools',
    ar: 'الأدوات الهندسية',
    ur: 'انجینئرنگ ٹولز',
    hi: 'इंजीनियरिंग टूल',
  );
  static const workshopTools = TranslatableString(
    en: 'Workshop tools',
    ar: 'أدوات الورشة',
    ur: 'ورکشاپ ٹولز',
    hi: 'वर्कशॉप टूल',
  );

  // ─── Role descriptions ──────────────────────────────────────────────────
  static const peDescription = TranslatableString(
    en: 'Approve requests, keep deliveries moving and confirm what reached site on your projects.',
    ar: 'اعتمد الطلبات وحافظ على سير التوريدات وأكّد ما وصل إلى الموقع في مشاريعك.',
    ur: 'ریکویسٹس منظور کریں، ترسیل جاری رکھیں اور اپنے پروجیکٹس پر سائٹ تک پہنچنے والی چیزوں کی تصدیق کریں۔',
    hi: 'रिक्वेस्ट स्वीकृत करें, डिलीवरी चलती रखें और अपने प्रोजेक्ट पर साइट तक पहुँची सामग्री की पुष्टि करें।',
  );
  static const seDescription = TranslatableString(
    en: 'Finish your drafts, confirm deliveries on site and send back what is not needed.',
    ar: 'أكمل مسوداتك وأكّد التوريدات في الموقع وأعد ما لا تحتاجه.',
    ur: 'اپنے ڈرافٹس مکمل کریں، سائٹ پر ترسیل کی تصدیق کریں اور غیر ضروری سامان واپس بھیجیں۔',
    hi: 'अपने ड्राफ्ट पूरे करें, साइट पर डिलीवरी की पुष्टि करें और जो ज़रूरी नहीं उसे वापस भेजें।',
  );
  static const procDescription = TranslatableString(
    en: 'Arrange approved requests, dispatch only what was approved and keep stock honest. Projects are view only.',
    ar: 'رتّب الطلبات المعتمدة وأرسل المعتمد فقط وحافظ على دقة المخزون. المشاريع للعرض فقط.',
    ur: 'منظور شدہ ریکویسٹس کا انتظام کریں، صرف منظور شدہ مقدار روانہ کریں اور اسٹاک درست رکھیں۔ پروجیکٹس صرف دیکھنے کے لیے ہیں۔',
    hi: 'स्वीकृत रिक्वेस्ट की व्यवस्था करें, केवल स्वीकृत मात्रा डिस्पैच करें और स्टॉक सही रखें। प्रोजेक्ट केवल देखने के लिए हैं।',
  );
  static const procScope = TranslatableString(
    en: 'All running projects · 1 warehouse',
    ar: 'كل المشاريع الجارية · مستودع واحد',
    ur: 'تمام جاری پروجیکٹس · 1 گودام',
    hi: 'सभी चालू प्रोजेक्ट · 1 गोदाम',
  );
  static const smeDescription = TranslatableString(
    en: 'Lead engineering decisions across Yorks: approvals, supply constraints and projects that still need a Project Engineer.',
    ar: 'قُد القرارات الهندسية في Yorks: الموافقات وقيود التوريد والمشاريع التي ما زالت تحتاج مهندس مشروع.',
    ur: 'Yorks میں انجینئرنگ فیصلوں کی قیادت کریں: منظوریاں، فراہمی کی رکاوٹیں اور وہ پروجیکٹس جنہیں ابھی پروجیکٹ انجینئر درکار ہے۔',
    hi: 'Yorks में इंजीनियरिंग निर्णयों का नेतृत्व करें: स्वीकृतियाँ, आपूर्ति बाधाएँ और ऐसे प्रोजेक्ट जिन्हें अभी प्रोजेक्ट इंजीनियर चाहिए।',
  );
  static const smeScope = TranslatableString(
    en: 'Organisation-wide · stock is read only',
    ar: 'على مستوى المؤسسة · المخزون للقراءة فقط',
    ur: 'پوری تنظیم · اسٹاک صرف دیکھنے کے لیے',
    hi: 'पूरे संगठन में · स्टॉक केवल पढ़ने के लिए',
  );
  static const pmDescription = TranslatableString(
    en: 'See which projects need a decision and where material is stuck across Yorks.',
    ar: 'اعرف المشاريع التي تحتاج قرارًا وأين تتعثر المواد في Yorks.',
    ur: 'دیکھیں کن پروجیکٹس کو فیصلہ درکار ہے اور Yorks میں سامان کہاں رکا ہوا ہے۔',
    hi: 'देखें किन प्रोजेक्ट को निर्णय चाहिए और Yorks में सामग्री कहाँ अटकी है।',
  );
  static const wicDescription = TranslatableString(
    en: 'Run the workshop day: the material the workshop needs, what you can approve and what is ready to go out.',
    ar: 'أدِر يوم الورشة: المواد التي تحتاجها وما يمكنك اعتماده وما هو جاهز للخروج.',
    ur: 'ورکشاپ کا دن چلائیں: ورکشاپ کو درکار سامان، جو آپ منظور کر سکتے ہیں اور جو روانگی کے لیے تیار ہے۔',
    hi: 'वर्कशॉप का दिन चलाएँ: वर्कशॉप की ज़रूरी सामग्री, जो आप स्वीकृत कर सकते हैं और जो बाहर जाने को तैयार है।',
  );
  static const dcDescription = TranslatableString(
    en: 'Keep every project’s controlled records complete: receipts, exceptions and requests ready to file.',
    ar: 'حافظ على اكتمال السجلات المضبوطة لكل مشروع: الاستلامات والاستثناءات والطلبات الجاهزة للحفظ.',
    ur: 'ہر پروجیکٹ کے کنٹرولڈ ریکارڈ مکمل رکھیں: وصولیاں، استثنا اور فائل کے لیے تیار ریکویسٹس۔',
    hi: 'हर प्रोजेक्ट के नियंत्रित रिकॉर्ड पूरे रखें: प्राप्तियाँ, अपवाद और फ़ाइल करने योग्य रिक्वेस्ट।',
  );
  static const adminDescription = TranslatableString(
    en: 'How Yorks is doing today, what is blocking work and where to look next.',
    ar: 'كيف تسير Yorks اليوم، وما الذي يعيق العمل، وأين تنظر بعد ذلك.',
    ur: 'آج Yorks کیسا چل رہا ہے، کام میں کیا رکاوٹ ہے اور آگے کہاں دیکھنا ہے۔',
    hi: 'आज Yorks कैसा चल रहा है, काम में क्या रुकावट है और आगे कहाँ देखना है।',
  );

  // ─── KPI tiles ──────────────────────────────────────────────────────────
  static const kpiWaitingApproval = TranslatableString(
    en: 'Waiting for your approval',
    ar: 'بانتظار موافقتك',
    ur: 'آپ کی منظوری کے منتظر',
    hi: 'आपकी स्वीकृति की प्रतीक्षा',
  );
  static const kpiWithProcurement = TranslatableString(
    en: 'With Procurement',
    ar: 'لدى المشتريات',
    ur: 'پروکیورمنٹ کے پاس',
    hi: 'प्रोक्योरमेंट के पास',
  );
  static const kpiWithProcurementSub = TranslatableString(
    en: 'Approved and being arranged',
    ar: 'معتمدة وقيد الترتيب',
    ur: 'منظور شدہ اور زیر انتظام',
    hi: 'स्वीकृत और व्यवस्था में',
  );
  static const kpiReceiptOpen = TranslatableString(
    en: 'Delivered, receipt open',
    ar: 'تم التوريد، الاستلام مفتوح',
    ur: 'پہنچا دیا گیا، وصولی باقی',
    hi: 'डिलीवर, प्राप्ति खुली',
  );
  static const kpiReceiptOpenSub = TranslatableString(
    en: 'Dispatched and waiting for receipt',
    ar: 'تم الإرسال وبانتظار الاستلام',
    ur: 'روانہ اور وصولی کے منتظر',
    hi: 'डिस्पैच और प्राप्ति की प्रतीक्षा में',
  );
  static const kpiReceiptOpenDcSub = TranslatableString(
    en: 'Receipt evidence still to come',
    ar: 'أدلة الاستلام لم تصل بعد',
    ur: 'وصولی کا ثبوت ابھی باقی ہے',
    hi: 'प्राप्ति का प्रमाण अभी बाकी',
  );
  static const kpiExceptions = TranslatableString(
    en: 'Exceptions',
    ar: 'الاستثناءات',
    ur: 'استثنا',
    hi: 'अपवाद',
  );
  static const kpiExceptionsSub = TranslatableString(
    en: 'Supply and receipt problems still open',
    ar: 'مشكلات توريد واستلام ما زالت مفتوحة',
    ur: 'فراہمی اور وصولی کے کھلے مسائل',
    hi: 'आपूर्ति और प्राप्ति की खुली समस्याएँ',
  );
  static const kpiDraftsChanges = TranslatableString(
    en: 'Drafts & changes',
    ar: 'المسودات والتعديلات',
    ur: 'ڈرافٹس اور تبدیلیاں',
    hi: 'ड्राफ्ट और बदलाव',
  );
  static const kpiDraftsChangesSub = TranslatableString(
    en: 'Not yet submitted or returned for changes',
    ar: 'لم تُقدَّم بعد أو أُعيدت للتعديل',
    ur: 'ابھی جمع نہیں یا تبدیلی کے لیے واپس',
    hi: 'अभी जमा नहीं या बदलाव के लिए लौटाई गई',
  );
  static const kpiDeliveriesToConfirm = TranslatableString(
    en: 'Deliveries to confirm',
    ar: 'توريدات للتأكيد',
    ur: 'تصدیق طلب ترسیلات',
    hi: 'पुष्टि हेतु डिलीवरी',
  );
  static const kpiDeliveriesToConfirmSub = TranslatableString(
    en: 'Delivered to your sites',
    ar: 'وصلت إلى مواقعك',
    ur: 'آپ کی سائٹس پر پہنچائی گئیں',
    hi: 'आपकी साइटों पर पहुँचाई गईं',
  );
  static const kpiReturnedForChanges = TranslatableString(
    en: 'Returned for changes',
    ar: 'أعيدت للتعديل',
    ur: 'تبدیلی کے لیے واپس',
    hi: 'बदलाव के लिए लौटाई गई',
  );
  static const kpiReturnedForChangesSub = TranslatableString(
    en: 'A Project Engineer asked for a change',
    ar: 'طلب مهندس المشروع تعديلًا',
    ur: 'پروجیکٹ انجینئر نے تبدیلی مانگی',
    hi: 'प्रोजेक्ट इंजीनियर ने बदलाव माँगा',
  );
  static const kpiMyDrafts = TranslatableString(
    en: 'My drafts',
    ar: 'مسوداتي',
    ur: 'میرے ڈرافٹس',
    hi: 'मेरे ड्राफ्ट',
  );
  static const kpiMyDraftsSub = TranslatableString(
    en: 'Visible only to you',
    ar: 'مرئية لك فقط',
    ur: 'صرف آپ کو نظر آتے ہیں',
    hi: 'केवल आपको दिखाई देते हैं',
  );
  static const kpiWaitingOnOthers = TranslatableString(
    en: 'Waiting on others',
    ar: 'بانتظار الآخرين',
    ur: 'دوسروں کے منتظر',
    hi: 'दूसरों की प्रतीक्षा में',
  );
  static const kpiWaitingOnOthersSub = TranslatableString(
    en: 'Approval, arrangement or dispatch',
    ar: 'موافقة أو ترتيب أو إرسال',
    ur: 'منظوری، انتظام یا روانگی',
    hi: 'स्वीकृति, व्यवस्था या डिस्पैच',
  );
  static const kpiMissingDamaged = TranslatableString(
    en: 'Missing or damaged',
    ar: 'مفقود أو تالف',
    ur: 'گمشدہ یا خراب',
    hi: 'गायब या क्षतिग्रस्त',
  );
  static const kpiMissingDamagedSub = TranslatableString(
    en: 'Replacement can be arranged',
    ar: 'يمكن ترتيب البديل',
    ur: 'متبادل کا انتظام ہو سکتا ہے',
    hi: 'प्रतिस्थापन की व्यवस्था हो सकती है',
  );
  static const kpiToArrange = TranslatableString(
    en: 'To arrange',
    ar: 'للترتيب',
    ur: 'انتظام کے لیے',
    hi: 'व्यवस्था हेतु',
  );
  static const kpiReadyToDispatch = TranslatableString(
    en: 'Ready to dispatch',
    ar: 'جاهز للإرسال',
    ur: 'روانگی کے لیے تیار',
    hi: 'डिस्पैच के लिए तैयार',
  );
  static const kpiSupplierLate = TranslatableString(
    en: 'Supplier deliveries late',
    ar: 'توريدات الموردين المتأخرة',
    ur: 'سپلائر کی ترسیل میں تاخیر',
    hi: 'सप्लायर डिलीवरी में देरी',
  );
  static const kpiSupplierLateSub = TranslatableString(
    en: 'Past the expected date',
    ar: 'تجاوزت التاريخ المتوقع',
    ur: 'متوقع تاریخ گزر چکی',
    hi: 'अपेक्षित तिथि निकल चुकी',
  );
  static const kpiWaitingSiteReceipt = TranslatableString(
    en: 'Waiting for site receipt',
    ar: 'بانتظار استلام الموقع',
    ur: 'سائٹ وصولی کے منتظر',
    hi: 'साइट प्राप्ति की प्रतीक्षा',
  );
  static const kpiWaitingSiteReceiptSub = TranslatableString(
    en: 'Dispatched, not yet confirmed',
    ar: 'أُرسلت ولم تُؤكد بعد',
    ur: 'روانہ، ابھی تصدیق نہیں ہوئی',
    hi: 'डिस्पैच, अभी पुष्टि नहीं',
  );
  static const kpiApprovalsWaiting = TranslatableString(
    en: 'Approvals waiting',
    ar: 'موافقات بالانتظار',
    ur: 'زیر التوا منظوریاں',
    hi: 'लंबित स्वीकृतियाँ',
  );
  static const kpiApprovalsDcSub = TranslatableString(
    en: 'You can approve as Project Engineer',
    ar: 'يمكنك الاعتماد بصفة مهندس مشروع',
    ur: 'آپ پروجیکٹ انجینئر کے طور پر منظور کر سکتے ہیں',
    hi: 'आप प्रोजेक्ट इंजीनियर के रूप में स्वीकृत कर सकते हैं',
  );
  static const kpiCannotSupply = TranslatableString(
    en: 'Supply constraints',
    ar: 'قيود التوريد',
    ur: 'فراہمی کی رکاوٹیں',
    hi: 'आपूर्ति बाधाएँ',
  );
  static const kpiCannotSupplySub = TranslatableString(
    en: 'Partial or cannot provide now',
    ar: 'جزئي أو غير متاح حاليًا',
    ur: 'جزوی یا ابھی دستیاب نہیں',
    hi: 'आंशिक या अभी उपलब्ध नहीं',
  );
  static const kpiNoProjectEngineer = TranslatableString(
    en: 'Projects without a Project Engineer',
    ar: 'مشاريع بلا مهندس مشروع',
    ur: 'پروجیکٹ انجینئر کے بغیر پروجیکٹس',
    hi: 'प्रोजेक्ट इंजीनियर के बिना प्रोजेक्ट',
  );
  static const kpiNoProjectEngineerSub = TranslatableString(
    en: 'A draft cannot be activated without one',
    ar: 'لا يمكن تفعيل المسودة بدونه',
    ur: 'اس کے بغیر ڈرافٹ فعال نہیں ہو سکتا',
    hi: 'इसके बिना ड्राफ्ट सक्रिय नहीं हो सकता',
  );
  static const kpiOpenRequests = TranslatableString(
    en: 'Open material requests',
    ar: 'طلبات المواد المفتوحة',
    ur: 'کھلی میٹریل ریکویسٹس',
    hi: 'खुली मटेरियल रिक्वेस्ट',
  );
  static const kpiOpenRequestsSub = TranslatableString(
    en: 'Submitted and not yet closed',
    ar: 'مقدّمة ولم تُغلق بعد',
    ur: 'جمع شدہ اور ابھی بند نہیں',
    hi: 'जमा और अभी बंद नहीं',
  );
  static const kpiActiveProjects = TranslatableString(
    en: 'Active projects',
    ar: 'المشاريع النشطة',
    ur: 'فعال پروجیکٹس',
    hi: 'सक्रिय प्रोजेक्ट',
  );
  static const kpiDeliveryExceptions = TranslatableString(
    en: 'Delivery exceptions',
    ar: 'استثناءات التوريد',
    ur: 'ترسیل کے استثنا',
    hi: 'डिलीवरी अपवाद',
  );
  static const kpiDeliveryExceptionsSub = TranslatableString(
    en: 'Partial, unavailable, missing or damaged',
    ar: 'جزئي أو غير متاح أو مفقود أو تالف',
    ur: 'جزوی، غیر دستیاب، گمشدہ یا خراب',
    hi: 'आंशिक, अनुपलब्ध, गायब या क्षतिग्रस्त',
  );
  static const kpiOnHold = TranslatableString(
    en: 'Projects on hold',
    ar: 'مشاريع معلقة',
    ur: 'روکے گئے پروجیکٹس',
    hi: 'रुके हुए प्रोजेक्ट',
  );
  static const kpiOnHoldSub = TranslatableString(
    en: 'New requests and dispatch are blocked',
    ar: 'الطلبات الجديدة والإرسال متوقفة',
    ur: 'نئی ریکویسٹس اور روانگی بند ہیں',
    hi: 'नई रिक्वेस्ट और डिस्पैच रुके हैं',
  );
  static const kpiReadyForDelivery = TranslatableString(
    en: 'Ready for delivery',
    ar: 'جاهز للتسليم',
    ur: 'ترسیل کے لیے تیار',
    hi: 'डिलीवरी के लिए तैयार',
  );
  static const kpiReadyForDeliverySub = TranslatableString(
    en: 'Approved and waiting for dispatch',
    ar: 'معتمد وبانتظار الإرسال',
    ur: 'منظور شدہ اور روانگی کے منتظر',
    hi: 'स्वीकृत और डिस्पैच की प्रतीक्षा में',
  );
  static const kpiReceiptExceptions = TranslatableString(
    en: 'Missing or damaged at receipt',
    ar: 'مفقود أو تالف عند الاستلام',
    ur: 'وصولی پر گمشدہ یا خراب',
    hi: 'प्राप्ति पर गायब या क्षतिग्रस्त',
  );
  static const kpiReceiptExceptionsSub = TranslatableString(
    en: 'Evidence to keep on file',
    ar: 'أدلة يجب حفظها',
    ur: 'فائل میں رکھنے کا ثبوت',
    hi: 'फ़ाइल में रखने योग्य प्रमाण',
  );
  static const kpiReadyToClose = TranslatableString(
    en: 'Received, ready to close',
    ar: 'مستلم وجاهز للإغلاق',
    ur: 'وصول شدہ، بند کرنے کے لیے تیار',
    hi: 'प्राप्त, बंद करने को तैयार',
  );
  static const kpiReadyToCloseSub = TranslatableString(
    en: 'All good material received',
    ar: 'استُلمت كل المواد السليمة',
    ur: 'تمام درست سامان وصول ہو گیا',
    hi: 'सारी अच्छी सामग्री प्राप्त',
  );
  static const kpiClosedThisWeek = TranslatableString(
    en: 'Closed this week',
    ar: 'أُغلقت هذا الأسبوع',
    ur: 'اس ہفتے بند ہوئیں',
    hi: 'इस सप्ताह बंद',
  );
  static const kpiClosedThisWeekSub = TranslatableString(
    en: 'Requests ready to file',
    ar: 'طلبات جاهزة للحفظ',
    ur: 'فائل کے لیے تیار ریکویسٹس',
    hi: 'फ़ाइल करने योग्य रिक्वेस्ट',
  );

  // ─── Cards ──────────────────────────────────────────────────────────────
  static const waitingForYou = TranslatableString(
    en: 'Waiting for you',
    ar: 'بانتظارك',
    ur: 'آپ کے منتظر',
    hi: 'आपकी प्रतीक्षा में',
  );
  static const waitingForYouSub = TranslatableString(
    en: 'Only records you can act on now, urgent and oldest first.',
    ar: 'السجلات التي يمكنك التصرف فيها الآن فقط، العاجل والأقدم أولًا.',
    ur: 'صرف وہ ریکارڈ جن پر آپ ابھی کارروائی کر سکتے ہیں، فوری اور پرانے پہلے۔',
    hi: 'केवल वे रिकॉर्ड जिन पर आप अभी कार्य कर सकते हैं, तत्काल और पुराने पहले।',
  );
  static const nothingWaitingForYou = TranslatableString(
    en: 'Nothing is waiting for you',
    ar: 'لا شيء بانتظارك',
    ur: 'آپ کے لیے کچھ زیر التوا نہیں',
    hi: 'आपके लिए कुछ भी लंबित नहीं',
  );
  static const nothingWaitingForYouBody = TranslatableString(
    en: 'No request, receipt or close-out needs your decision right now.',
    ar: 'لا يوجد طلب أو استلام أو إغلاق يحتاج قرارك الآن.',
    ur: 'اس وقت کسی ریکویسٹ، وصولی یا اختتام کو آپ کے فیصلے کی ضرورت نہیں۔',
    hi: 'अभी किसी रिक्वेस्ट, प्राप्ति या समापन को आपके निर्णय की ज़रूरत नहीं।',
  );
  static const ageFootnote = TranslatableString(
    en: 'Age is time in the current step. Action due dates are not configured, so none are guessed.',
    ar: 'العمر هو الوقت في الخطوة الحالية. لم تُضبط مواعيد استحقاق الإجراءات، لذا لا يتم تخمينها.',
    ur: 'عمر موجودہ مرحلے میں گزرا وقت ہے۔ کارروائی کی آخری تاریخیں ترتیب نہیں دی گئیں، اس لیے اندازہ نہیں لگایا جاتا۔',
    hi: 'आयु वर्तमान चरण में बीता समय है। कार्रवाई की नियत तिथियाँ कॉन्फ़िगर नहीं हैं, इसलिए अनुमान नहीं लगाया जाता।',
  );
  static const tabAll = TranslatableString(
    en: 'All',
    ar: 'الكل',
    ur: 'تمام',
    hi: 'सभी',
  );
  static const tabApprove = TranslatableString(
    en: 'Approve',
    ar: 'اعتماد',
    ur: 'منظوری',
    hi: 'स्वीकृति',
  );
  static const tabReceipts = TranslatableString(
    en: 'Receipts',
    ar: 'الاستلامات',
    ur: 'وصولیاں',
    hi: 'प्राप्तियाँ',
  );
  static const tabClose = TranslatableString(
    en: 'Close',
    ar: 'إغلاق',
    ur: 'بند کریں',
    hi: 'बंद करें',
  );
  static const tabChanges = TranslatableString(
    en: 'Changes',
    ar: 'التعديلات',
    ur: 'تبدیلیاں',
    hi: 'बदलाव',
  );
  static const tabDrafts = TranslatableString(
    en: 'Drafts',
    ar: 'المسودات',
    ur: 'ڈرافٹس',
    hi: 'ड्राफ्ट',
  );
  static const tabToArrange = TranslatableString(
    en: 'To arrange',
    ar: 'للترتيب',
    ur: 'انتظام کے لیے',
    hi: 'व्यवस्था हेतु',
  );
  static const tabToDispatch = TranslatableString(
    en: 'To dispatch',
    ar: 'للإرسال',
    ur: 'روانگی کے لیے',
    hi: 'डिस्पैच हेतु',
  );
  static const requestsOnMyProjects = TranslatableString(
    en: 'Requests on my projects',
    ar: 'الطلبات في مشاريعي',
    ur: 'میرے پروجیکٹس کی ریکویسٹس',
    hi: 'मेरे प्रोजेक्ट की रिक्वेस्ट',
  );
  static const requestsByStage = TranslatableString(
    en: 'Requests by stage',
    ar: 'الطلبات حسب المرحلة',
    ur: 'مرحلہ وار ریکویسٹس',
    hi: 'चरण अनुसार रिक्वेस्ट',
  );
  static const requestsByStageSub = TranslatableString(
    en: 'Open requests by stage. Select a stage to open the register.',
    ar: 'الطلبات المفتوحة حسب المرحلة. اختر مرحلة لفتح السجل.',
    ur: 'کھلی ریکویسٹس مرحلہ وار۔ رجسٹر کھولنے کے لیے مرحلہ منتخب کریں۔',
    hi: 'चरण अनुसार खुली रिक्वेस्ट। रजिस्टर खोलने के लिए चरण चुनें।',
  );
  static const pipelineFootnote = TranslatableString(
    en: 'Private drafts and closed requests are not counted.',
    ar: 'لا تُحتسب المسودات الخاصة والطلبات المغلقة.',
    ur: 'نجی ڈرافٹس اور بند ریکویسٹس شمار نہیں ہوتیں۔',
    hi: 'निजी ड्राफ्ट और बंद रिक्वेस्ट गिनी नहीं जातीं।',
  );
  static const stageCreated = TranslatableString(
    en: 'Created',
    ar: 'أُنشئ',
    ur: 'بنایا گیا',
    hi: 'बनाया गया',
  );
  static const stageEngineeringApproval = TranslatableString(
    en: 'Engineering approval',
    ar: 'الموافقة الهندسية',
    ur: 'انجینئرنگ منظوری',
    hi: 'इंजीनियरिंग स्वीकृति',
  );
  static const stageProcurementArrangement = TranslatableString(
    en: 'Procurement arrangement',
    ar: 'ترتيب المشتريات',
    ur: 'پروکیورمنٹ انتظام',
    hi: 'प्रोक्योरमेंट व्यवस्था',
  );
  static const stageReadyForDelivery = TranslatableString(
    en: 'Ready for delivery',
    ar: 'جاهز للتسليم',
    ur: 'ترسیل کے لیے تیار',
    hi: 'डिलीवरी के लिए तैयार',
  );
  static const stageDispatched = TranslatableString(
    en: 'Dispatched',
    ar: 'تم الإرسال',
    ur: 'روانہ',
    hi: 'डिस्पैच',
  );
  static const stageDispatchedHint = TranslatableString(
    en: 'Receipt open',
    ar: 'الاستلام مفتوح',
    ur: 'وصولی باقی',
    hi: 'प्राप्ति खुली',
  );
  static const stageReceived = TranslatableString(
    en: 'Received',
    ar: 'تم الاستلام',
    ur: 'وصول شدہ',
    hi: 'प्राप्त',
  );
  static const stageReceivedHint = TranslatableString(
    en: 'Ready to close',
    ar: 'جاهز للإغلاق',
    ur: 'بند کرنے کے لیے تیار',
    hi: 'बंद करने को तैयार',
  );
  static const stageCompleted = TranslatableString(
    en: 'Completed',
    ar: 'مكتمل',
    ur: 'مکمل',
    hi: 'पूर्ण',
  );
  static const stageApprovedToArrange = TranslatableString(
    en: 'Approved · to arrange',
    ar: 'معتمد · للترتيب',
    ur: 'منظور شدہ · انتظام کے لیے',
    hi: 'स्वीकृत · व्यवस्था हेतु',
  );
  static const stageWaitingEngineering = TranslatableString(
    en: 'With Engineering',
    ar: 'لدى الهندسة',
    ur: 'انجینئرنگ کے پاس',
    hi: 'इंजीनियरिंग के पास',
  );
  static const stageWaitingEngineeringHint = TranslatableString(
    en: 'Approval before or after arrangement',
    ar: 'موافقة قبل الترتيب أو بعده',
    ur: 'انتظام سے پہلے یا بعد منظوری',
    hi: 'व्यवस्था से पहले या बाद स्वीकृति',
  );
  static const stageReadyToDispatch = TranslatableString(
    en: 'Ready to dispatch',
    ar: 'جاهز للإرسال',
    ur: 'روانگی کے لیے تیار',
    hi: 'डिस्पैच के लिए तैयार',
  );
  static const stageDispatchedReceiptOpen = TranslatableString(
    en: 'Dispatched · site receipt open',
    ar: 'أُرسل · استلام الموقع مفتوح',
    ur: 'روانہ · سائٹ وصولی باقی',
    hi: 'डिस्पैच · साइट प्राप्ति खुली',
  );
  static const exceptionsToFollowUp = TranslatableString(
    en: 'Exceptions to follow up',
    ar: 'استثناءات للمتابعة',
    ur: 'پیروی طلب استثنا',
    hi: 'अनुवर्ती अपवाद',
  );
  static const exceptionsToFollowUpSub = TranslatableString(
    en: 'Supply and receipt problems still open.',
    ar: 'مشكلات توريد واستلام ما زالت مفتوحة.',
    ur: 'فراہمی اور وصولی کے کھلے مسائل۔',
    hi: 'आपूर्ति और प्राप्ति की खुली समस्याएँ।',
  );
  static const noExceptions = TranslatableString(
    en: 'No open supply or receipt problems.',
    ar: 'لا توجد مشكلات توريد أو استلام مفتوحة.',
    ur: 'فراہمی یا وصولی کا کوئی کھلا مسئلہ نہیں۔',
    hi: 'आपूर्ति या प्राप्ति की कोई खुली समस्या नहीं।',
  );
  static const deliveryExceptions = TranslatableString(
    en: 'Delivery exceptions',
    ar: 'استثناءات التوريد',
    ur: 'ترسیل کے استثنا',
    hi: 'डिलीवरी अपवाद',
  );
  static const neededThisWeek = TranslatableString(
    en: 'Needed on site this week',
    ar: 'مطلوب في الموقع هذا الأسبوع',
    ur: 'اس ہفتے سائٹ پر درکار',
    hi: 'इस सप्ताह साइट पर आवश्यक',
  );
  static const neededThisWeekSub = TranslatableString(
    en: 'Scheduled requests and their required date.',
    ar: 'الطلبات المجدولة وتاريخها المطلوب.',
    ur: 'شیڈول شدہ ریکویسٹس اور ان کی مطلوبہ تاریخ۔',
    hi: 'निर्धारित रिक्वेस्ट और उनकी आवश्यक तिथि।',
  );
  static const nothingNeededThisWeek = TranslatableString(
    en: 'No scheduled request is due in the next 7 days.',
    ar: 'لا يوجد طلب مجدول مستحق خلال 7 أيام.',
    ur: 'اگلے 7 دنوں میں کوئی شیڈول شدہ ریکویسٹ واجب نہیں۔',
    hi: 'अगले 7 दिनों में कोई निर्धारित रिक्वेस्ट देय नहीं।',
  );
  static const myProjects = TranslatableString(
    en: 'My projects',
    ar: 'مشاريعي',
    ur: 'میرے پروجیکٹس',
    hi: 'मेरे प्रोजेक्ट',
  );
  static const myProjectsSub = TranslatableString(
    en: 'Where each of your projects stands today.',
    ar: 'وضع كل مشروع من مشاريعك اليوم.',
    ur: 'آج آپ کا ہر پروجیکٹ کہاں کھڑا ہے۔',
    hi: 'आज आपका हर प्रोजेक्ट कहाँ है।',
  );
  static const colProject = TranslatableString(
    en: 'Project',
    ar: 'المشروع',
    ur: 'پروجیکٹ',
    hi: 'प्रोजेक्ट',
  );
  static const colState = TranslatableString(
    en: 'State',
    ar: 'الحالة',
    ur: 'حالت',
    hi: 'स्थिति',
  );
  static const colWaitingOnYou = TranslatableString(
    en: 'Waiting on you',
    ar: 'بانتظارك',
    ur: 'آپ کے منتظر',
    hi: 'आपकी प्रतीक्षा',
  );
  static const colExceptions = TranslatableString(
    en: 'Exceptions',
    ar: 'الاستثناءات',
    ur: 'استثنا',
    hi: 'अपवाद',
  );
  static const colTeam = TranslatableString(
    en: 'Team',
    ar: 'الفريق',
    ur: 'ٹیم',
    hi: 'टीम',
  );
  static const colLastUpdated = TranslatableString(
    en: 'Last updated',
    ar: 'آخر تحديث',
    ur: 'آخری اپڈیٹ',
    hi: 'अंतिम अपडेट',
  );
  static const noProjectEngineer = TranslatableString(
    en: 'No Project Engineer',
    ar: 'بلا مهندس مشروع',
    ur: 'پروجیکٹ انجینئر نہیں',
    hi: 'प्रोजेक्ट इंजीनियर नहीं',
  );
  static const noProjectsYet = TranslatableString(
    en: 'No project is assigned to you yet.',
    ar: 'لم يُسند إليك أي مشروع بعد.',
    ur: 'ابھی آپ کو کوئی پروجیکٹ تفویض نہیں ہوا۔',
    hi: 'अभी आपको कोई प्रोजेक्ट नहीं सौंपा गया।',
  );
  static const noProjectsNeedAttention = TranslatableString(
    en: 'No project has open exceptions, missing engineers or a hold.',
    ar: 'لا يوجد مشروع به استثناءات مفتوحة أو نقص مهندسين أو تعليق.',
    ur: 'کسی پروجیکٹ میں کھلے استثنا، انجینئر کی کمی یا رکاوٹ نہیں۔',
    hi: 'किसी प्रोजेक्ट में खुले अपवाद, इंजीनियर की कमी या रोक नहीं।',
  );
  static const toDoOnSite = TranslatableString(
    en: 'To do on site',
    ar: 'مهام في الموقع',
    ur: 'سائٹ پر کرنے کے کام',
    hi: 'साइट पर करने के काम',
  );
  static const toDoOnSiteSub = TranslatableString(
    en: 'Finish these first. Each one opens the exact record.',
    ar: 'أنجز هذه أولًا. كل عنصر يفتح السجل نفسه.',
    ur: 'یہ پہلے مکمل کریں۔ ہر ایک درست ریکارڈ کھولتا ہے۔',
    hi: 'इन्हें पहले पूरा करें। हर एक सही रिकॉर्ड खोलता है।',
  );
  static const upToDate = TranslatableString(
    en: 'You are up to date',
    ar: 'أنت على اطلاع كامل',
    ur: 'آپ کا کام مکمل ہے',
    hi: 'आपका काम अद्यतन है',
  );
  static const upToDateBody = TranslatableString(
    en: 'No delivery, change or draft is waiting for you.',
    ar: 'لا يوجد توريد أو تعديل أو مسودة بانتظارك.',
    ur: 'کوئی ترسیل، تبدیلی یا ڈرافٹ آپ کا منتظر نہیں۔',
    hi: 'कोई डिलीवरी, बदलाव या ड्राफ्ट आपकी प्रतीक्षा में नहीं।',
  );
  static const seFootnote = TranslatableString(
    en: 'Drafts stay private until you submit. Receipts record every line as Received, Missing or Damaged.',
    ar: 'تبقى المسودات خاصة حتى تقديمها. يسجل الاستلام كل بند كمستلم أو مفقود أو تالف.',
    ur: 'ڈرافٹس جمع کرانے تک نجی رہتے ہیں۔ وصولی ہر لائن کو وصول شدہ، گمشدہ یا خراب درج کرتی ہے۔',
    hi: 'ड्राफ्ट जमा करने तक निजी रहते हैं। प्राप्ति हर लाइन को प्राप्त, गायब या क्षतिग्रस्त दर्ज करती है।',
  );
  static const myRequests = TranslatableString(
    en: 'My requests',
    ar: 'طلباتي',
    ur: 'میری ریکویسٹس',
    hi: 'मेरी रिक्वेस्ट',
  );
  static const myRequestsSub = TranslatableString(
    en: 'Where each submitted request is and who has it now.',
    ar: 'أين يقع كل طلب مقدّم ومن لديه الآن.',
    ur: 'ہر جمع شدہ ریکویسٹ کہاں ہے اور ابھی کس کے پاس ہے۔',
    hi: 'हर जमा रिक्वेस्ट कहाँ है और अभी किसके पास है।',
  );
  static const noOpenRequests = TranslatableString(
    en: 'You have no open request.',
    ar: 'ليس لديك طلب مفتوح.',
    ur: 'آپ کی کوئی کھلی ریکویسٹ نہیں۔',
    hi: 'आपकी कोई खुली रिक्वेस्ट नहीं।',
  );
  static const onTheWay = TranslatableString(
    en: 'On the way to your sites',
    ar: 'في الطريق إلى مواقعك',
    ur: 'آپ کی سائٹس کی طرف راستے میں',
    hi: 'आपकी साइटों की ओर रास्ते में',
  );
  static const onTheWaySub = TranslatableString(
    en: 'Dispatched or packed and ready.',
    ar: 'مرسلة أو معبأة وجاهزة.',
    ur: 'روانہ یا پیک اور تیار۔',
    hi: 'डिस्पैच या पैक और तैयार।',
  );
  static const nothingOnTheWay = TranslatableString(
    en: 'Nothing is on the way right now.',
    ar: 'لا شيء في الطريق حاليًا.',
    ur: 'اس وقت کچھ راستے میں نہیں۔',
    hi: 'अभी कुछ भी रास्ते में नहीं।',
  );
  static const missingOrDamaged = TranslatableString(
    en: 'Missing or damaged',
    ar: 'مفقود أو تالف',
    ur: 'گمشدہ یا خراب',
    hi: 'गायब या क्षतिग्रस्त',
  );
  static const missingOrDamagedSub = TranslatableString(
    en: 'Procurement can replace up to the approved quantity.',
    ar: 'يمكن للمشتريات الاستبدال حتى الكمية المعتمدة.',
    ur: 'پروکیورمنٹ منظور شدہ مقدار تک متبادل دے سکتی ہے۔',
    hi: 'प्रोक्योरमेंट स्वीकृत मात्रा तक प्रतिस्थापन कर सकता है।',
  );
  static const nothingMissing = TranslatableString(
    en: 'Nothing is missing or damaged.',
    ar: 'لا يوجد مفقود أو تالف.',
    ur: 'کچھ گمشدہ یا خراب نہیں۔',
    hi: 'कुछ भी गायब या क्षतिग्रस्त नहीं।',
  );
  static const yourWorkQueue = TranslatableString(
    en: 'Your work queue',
    ar: 'قائمة عملك',
    ur: 'آپ کی کام کی فہرست',
    hi: 'आपकी कार्य सूची',
  );
  static const yourWorkQueueSub = TranslatableString(
    en: 'Approved by Engineering and ready for you. Urgent and oldest first.',
    ar: 'معتمدة من الهندسة وجاهزة لك. العاجل والأقدم أولًا.',
    ur: 'انجینئرنگ سے منظور اور آپ کے لیے تیار۔ فوری اور پرانے پہلے۔',
    hi: 'इंजीनियरिंग द्वारा स्वीकृत और आपके लिए तैयार। तत्काल और पुराने पहले।',
  );
  static const nothingForProcurement = TranslatableString(
    en: 'Nothing needs Procurement right now',
    ar: 'لا شيء يحتاج المشتريات الآن',
    ur: 'اس وقت پروکیورمنٹ کے لیے کچھ نہیں',
    hi: 'अभी प्रोक्योरमेंट के लिए कुछ नहीं',
  );
  static const nothingForProcurementBody = TranslatableString(
    en: 'New approved requests appear here the moment Engineering approves them.',
    ar: 'تظهر الطلبات المعتمدة الجديدة هنا فور اعتمادها من الهندسة.',
    ur: 'نئی منظور شدہ ریکویسٹس انجینئرنگ کی منظوری کے فوراً بعد یہاں ظاہر ہوتی ہیں۔',
    hi: 'नई स्वीकृत रिक्वेस्ट इंजीनियरिंग की स्वीकृति होते ही यहाँ दिखती हैं।',
  );
  static const procFootnote = TranslatableString(
    en: 'Saving an arrangement replaces reservations in one step. Dispatch never exceeds the approved quantity or available stock.',
    ar: 'حفظ الترتيب يستبدل الحجوزات في خطوة واحدة. لا يتجاوز الإرسال الكمية المعتمدة أو المخزون المتاح.',
    ur: 'انتظام محفوظ کرنے سے ریزرویشنز ایک قدم میں بدل جاتی ہیں۔ روانگی کبھی منظور شدہ مقدار یا دستیاب اسٹاک سے زیادہ نہیں ہوتی۔',
    hi: 'व्यवस्था सहेजने से आरक्षण एक चरण में बदल जाते हैं। डिस्पैच कभी स्वीकृत मात्रा या उपलब्ध स्टॉक से अधिक नहीं होता।',
  );
  static const belowMinimumStock = TranslatableString(
    en: 'Below minimum stock',
    ar: 'أقل من الحد الأدنى للمخزون',
    ur: 'کم از کم اسٹاک سے کم',
    hi: 'न्यूनतम स्टॉक से कम',
  );
  static const belowMinimumSub = TranslatableString(
    en: '{n} items. The lowest available are listed first.',
    ar: '{n} أصناف. الأقل توفرًا أولًا.',
    ur: '{n} اشیاء۔ سب سے کم دستیاب پہلے۔',
    hi: '{n} आइटम। सबसे कम उपलब्ध पहले।',
  );
  static const belowMinimumSubReadOnly = TranslatableString(
    en: '{n} items · read only. The lowest available are listed first.',
    ar: '{n} أصناف · للقراءة فقط. الأقل توفرًا أولًا.',
    ur: '{n} اشیاء · صرف دیکھنے کے لیے۔ سب سے کم دستیاب پہلے۔',
    hi: '{n} आइटम · केवल पढ़ने के लिए। सबसे कम उपलब्ध पहले।',
  );
  static const noLowStock = TranslatableString(
    en: 'Every item is at or above its minimum.',
    ar: 'كل الأصناف عند الحد الأدنى أو فوقه.',
    ur: 'ہر چیز کم از کم حد پر یا اس سے زیادہ ہے۔',
    hi: 'हर आइटम अपने न्यूनतम पर या उससे ऊपर है।',
  );
  static const colItem = TranslatableString(
    en: 'Item',
    ar: 'الصنف',
    ur: 'آئٹم',
    hi: 'आइटम',
  );
  static const colOnHand = TranslatableString(
    en: 'On hand',
    ar: 'المتوفر',
    ur: 'موجود',
    hi: 'उपलब्ध भंडार',
  );
  static const colReserved = TranslatableString(
    en: 'Reserved',
    ar: 'محجوز',
    ur: 'محفوظ',
    hi: 'आरक्षित',
  );
  static const colAvailable = TranslatableString(
    en: 'Available',
    ar: 'المتاح',
    ur: 'دستیاب',
    hi: 'उपलब्ध',
  );
  static const colMinimum = TranslatableString(
    en: 'Minimum',
    ar: 'الحد الأدنى',
    ur: 'کم از کم',
    hi: 'न्यूनतम',
  );
  static const yourPipeline = TranslatableString(
    en: 'Your pipeline',
    ar: 'مسار عملك',
    ur: 'آپ کی پائپ لائن',
    hi: 'आपकी पाइपलाइन',
  );
  static const yourPipelineSub = TranslatableString(
    en: 'Engineering approves first, then you arrange and dispatch.',
    ar: 'تعتمد الهندسة أولًا، ثم ترتب وترسل.',
    ur: 'پہلے انجینئرنگ منظور کرتی ہے، پھر آپ انتظام اور روانگی کرتے ہیں۔',
    hi: 'पहले इंजीनियरिंग स्वीकृत करती है, फिर आप व्यवस्था और डिस्पैच करते हैं।',
  );
  static const supplierDeliveries = TranslatableString(
    en: 'Supplier deliveries',
    ar: 'توريدات الموردين',
    ur: 'سپلائر ترسیلات',
    hi: 'सप्लायर डिलीवरी',
  );
  static const supplierDeliveriesSub = TranslatableString(
    en: 'Lines that are late from a supplier or cannot be provided now.',
    ar: 'بنود متأخرة من المورد أو غير متاحة حاليًا.',
    ur: 'سپلائر سے تاخیر یا ابھی فراہم نہ ہو سکنے والی لائنیں۔',
    hi: 'सप्लायर से देर या अभी उपलब्ध न होने वाली लाइनें।',
  );
  static const waitingForSiteReceipt = TranslatableString(
    en: 'Waiting for site receipt',
    ar: 'بانتظار استلام الموقع',
    ur: 'سائٹ وصولی کے منتظر',
    hi: 'साइट प्राप्ति की प्रतीक्षा',
  );
  static const waitingForSiteReceiptSub = TranslatableString(
    en: 'Dispatched, but the site has not confirmed yet.',
    ar: 'أُرسلت لكن الموقع لم يؤكد بعد.',
    ur: 'روانہ، لیکن سائٹ نے ابھی تصدیق نہیں کی۔',
    hi: 'डिस्पैच, पर साइट ने अभी पुष्टि नहीं की।',
  );
  static const nothingAwaitingReceipt = TranslatableString(
    en: 'Every dispatch has been confirmed by site.',
    ar: 'أكد الموقع كل الإرساليات.',
    ur: 'سائٹ نے ہر روانگی کی تصدیق کر دی ہے۔',
    hi: 'साइट ने हर डिस्पैच की पुष्टि कर दी है।',
  );
  static const last30Days = TranslatableString(
    en: 'Last 30 days',
    ar: 'آخر 30 يومًا',
    ur: 'گزشتہ 30 دن',
    hi: 'पिछले 30 दिन',
  );
  static const last30DaysSub = TranslatableString(
    en: 'No cost values. Empty samples show a dash.',
    ar: 'بدون قيم تكلفة. العينات الفارغة تظهر بشرطة.',
    ur: 'کوئی لاگت کی قدر نہیں۔ خالی نمونے ڈیش دکھاتے ہیں۔',
    hi: 'कोई लागत मूल्य नहीं। खाली नमूने डैश दिखाते हैं।',
  );
  static const avgArrangementTime = TranslatableString(
    en: 'Average arrangement time',
    ar: 'متوسط زمن الترتيب',
    ur: 'اوسط انتظامی وقت',
    hi: 'औसत व्यवस्था समय',
  );
  static const warehouseFillRate = TranslatableString(
    en: 'Warehouse fill rate',
    ar: 'نسبة التلبية من المستودع',
    ur: 'گودام فل ریٹ',
    hi: 'गोदाम पूर्ति दर',
  );
  static const avgReceiptTime = TranslatableString(
    en: 'Average site receipt time',
    ar: 'متوسط زمن استلام الموقع',
    ur: 'اوسط سائٹ وصولی وقت',
    hi: 'औसत साइट प्राप्ति समय',
  );
  static const replacementOwed = TranslatableString(
    en: 'Replacement still owed',
    ar: 'بدائل مستحقة',
    ur: 'باقی متبادل',
    hi: 'बकाया प्रतिस्थापन',
  );
  static const approvalsAcrossYorks = TranslatableString(
    en: 'Approvals you can make',
    ar: 'موافقات يمكنك إجراؤها',
    ur: 'منظوریاں جو آپ دے سکتے ہیں',
    hi: 'स्वीकृतियाँ जो आप दे सकते हैं',
  );
  static const smeApprovalsSub = TranslatableString(
    en: 'You can approve any project as an organisation-wide Project Engineer. Oldest first.',
    ar: 'يمكنك اعتماد أي مشروع بصفتك مهندس مشروع على مستوى المؤسسة. الأقدم أولًا.',
    ur: 'آپ تنظیمی سطح کے پروجیکٹ انجینئر کے طور پر کوئی بھی پروجیکٹ منظور کر سکتے ہیں۔ پرانے پہلے۔',
    hi: 'आप संगठन-स्तरीय प्रोजेक्ट इंजीनियर के रूप में कोई भी प्रोजेक्ट स्वीकृत कर सकते हैं। पुराने पहले।',
  );
  static const pmApprovalsSub = TranslatableString(
    en: 'You approve as an organisation-wide Project Engineer. Oldest first.',
    ar: 'تعتمد بصفتك مهندس مشروع على مستوى المؤسسة. الأقدم أولًا.',
    ur: 'آپ تنظیمی سطح کے پروجیکٹ انجینئر کے طور پر منظوری دیتے ہیں۔ پرانے پہلے۔',
    hi: 'आप संगठन-स्तरीय प्रोजेक्ट इंजीनियर के रूप में स्वीकृति देते हैं। पुराने पहले।',
  );
  static const noApprovalsWaiting = TranslatableString(
    en: 'No approval is waiting',
    ar: 'لا توجد موافقة بالانتظار',
    ur: 'کوئی منظوری زیر التوا نہیں',
    hi: 'कोई स्वीकृति लंबित नहीं',
  );
  static const noApprovalsWaitingBody = TranslatableString(
    en: 'New requests appear here as soon as they are submitted.',
    ar: 'تظهر الطلبات الجديدة هنا فور تقديمها.',
    ur: 'نئی ریکویسٹس جمع ہوتے ہی یہاں ظاہر ہوتی ہیں۔',
    hi: 'नई रिक्वेस्ट जमा होते ही यहाँ दिखती हैं।',
  );
  static const supplyConstraints = TranslatableString(
    en: 'Supply constraints',
    ar: 'قيود التوريد',
    ur: 'فراہمی کی رکاوٹیں',
    hi: 'आपूर्ति बाधाएँ',
  );
  static const supplyConstraintsSub = TranslatableString(
    en: 'Requests Procurement could not fully supply or that wait on a supplier.',
    ar: 'طلبات لم تتمكن المشتريات من توريدها بالكامل أو تنتظر موردًا.',
    ur: 'وہ ریکویسٹس جو پروکیورمنٹ مکمل فراہم نہ کر سکی یا سپلائر کی منتظر ہیں۔',
    hi: 'वे रिक्वेस्ट जिन्हें प्रोक्योरमेंट पूरा नहीं दे सका या जो सप्लायर की प्रतीक्षा में हैं।',
  );
  static const projectsWithoutPe = TranslatableString(
    en: 'Projects without a Project Engineer',
    ar: 'مشاريع بلا مهندس مشروع',
    ur: 'پروجیکٹ انجینئر کے بغیر پروجیکٹس',
    hi: 'प्रोजेक्ट इंजीनियर के बिना प्रोजेक्ट',
  );
  static const projectsWithoutPeSub = TranslatableString(
    en: 'Activation and approvals need at least one.',
    ar: 'يتطلب التفعيل والموافقات واحدًا على الأقل.',
    ur: 'فعال کرنے اور منظوری کے لیے کم از کم ایک درکار ہے۔',
    hi: 'सक्रियण और स्वीकृति के लिए कम से कम एक चाहिए।',
  );
  static const everyProjectHasPe = TranslatableString(
    en: 'Every running project has a Project Engineer.',
    ar: 'لكل مشروع جارٍ مهندس مشروع.',
    ur: 'ہر جاری پروجیکٹ کا پروجیکٹ انجینئر ہے۔',
    hi: 'हर चालू प्रोजेक्ट में प्रोजेक्ट इंजीनियर है।',
  );
  static const allMaterialRequests = TranslatableString(
    en: 'All material requests',
    ar: 'كل طلبات المواد',
    ur: 'تمام میٹریل ریکویسٹس',
    hi: 'सभी मटेरियल रिक्वेस्ट',
  );
  static const projectsNeedingAttention = TranslatableString(
    en: 'Projects needing attention',
    ar: 'مشاريع تحتاج اهتمامًا',
    ur: 'توجہ طلب پروجیکٹس',
    hi: 'ध्यान देने योग्य प्रोजेक्ट',
  );
  static const projectsNeedingAttentionSub = TranslatableString(
    en: 'Sorted by what is blocking delivery: exceptions, holds and missing engineers.',
    ar: 'مرتبة حسب ما يعيق التوريد: الاستثناءات والتعليق ونقص المهندسين.',
    ur: 'ترسیل روکنے والی چیزوں کے لحاظ سے: استثنا، رکاوٹیں اور انجینئر کی کمی۔',
    hi: 'डिलीवरी रोकने वाली बातों के अनुसार: अपवाद, रोक और इंजीनियर की कमी।',
  );
  static const projectsOnHold = TranslatableString(
    en: 'Projects on hold',
    ar: 'مشاريع معلقة',
    ur: 'روکے گئے پروجیکٹس',
    hi: 'रुके हुए प्रोजेक्ट',
  );
  static const projectsOnHoldSub = TranslatableString(
    en: 'New requests and dispatch are blocked.',
    ar: 'الطلبات الجديدة والإرسال متوقفة.',
    ur: 'نئی ریکویسٹس اور روانگی بند ہیں۔',
    hi: 'नई रिक्वेस्ट और डिस्पैच रुके हैं।',
  );
  static const noProjectsOnHold = TranslatableString(
    en: 'No project is on hold.',
    ar: 'لا يوجد مشروع معلق.',
    ur: 'کوئی پروجیکٹ روکا نہیں گیا۔',
    hi: 'कोई प्रोजेक्ट रुका नहीं है।',
  );
  static const yourNextActions = TranslatableString(
    en: 'Your next actions',
    ar: 'إجراءاتك التالية',
    ur: 'آپ کے اگلے اقدامات',
    hi: 'आपकी अगली कार्रवाइयाँ',
  );
  static const yourNextActionsSub = TranslatableString(
    en: 'Material decisions you can make now, oldest first.',
    ar: 'قرارات المواد التي يمكنك اتخاذها الآن، الأقدم أولًا.',
    ur: 'سامان کے فیصلے جو آپ ابھی کر سکتے ہیں، پرانے پہلے۔',
    hi: 'सामग्री निर्णय जो आप अभी ले सकते हैं, पुराने पहले।',
  );
  static const receiptEvidence = TranslatableString(
    en: 'Receipt evidence to file',
    ar: 'أدلة استلام للحفظ',
    ur: 'فائل کے لیے وصولی کا ثبوت',
    hi: 'फ़ाइल हेतु प्राप्ति प्रमाण',
  );
  static const receiptEvidenceSub = TranslatableString(
    en: 'Missing or damaged lines and the replacements they need.',
    ar: 'بنود مفقودة أو تالفة والبدائل التي تحتاجها.',
    ur: 'گمشدہ یا خراب لائنیں اور ان کے متبادل۔',
    hi: 'गायब या क्षतिग्रस्त लाइनें और उनके प्रतिस्थापन।',
  );
  static const closedThisWeek = TranslatableString(
    en: 'Closed this week',
    ar: 'أُغلقت هذا الأسبوع',
    ur: 'اس ہفتے بند ہوئیں',
    hi: 'इस सप्ताह बंद',
  );
  static const closedThisWeekSub = TranslatableString(
    en: 'Ready to file with their Delivery Orders and receipts.',
    ar: 'جاهزة للحفظ مع أوامر التسليم والاستلامات.',
    ur: 'ڈیلیوری آرڈرز اور وصولیوں کے ساتھ فائل کے لیے تیار۔',
    hi: 'डिलीवरी ऑर्डर और प्राप्तियों के साथ फ़ाइल करने को तैयार।',
  );
  static const nothingClosedThisWeek = TranslatableString(
    en: 'No request was closed in the last 7 days.',
    ar: 'لم يُغلق أي طلب خلال آخر 7 أيام.',
    ur: 'گزشتہ 7 دنوں میں کوئی ریکویسٹ بند نہیں ہوئی۔',
    hi: 'पिछले 7 दिनों में कोई रिक्वेस्ट बंद नहीं हुई।',
  );

  // ─── PR (HR/PRO): people, attendance and rentals ─────────────────────────────────────
  static const prDescription = TranslatableString(
    en: 'People, their documents and attendance: what needs attention today.',
    ar: 'الأفراد ومستنداتهم والحضور: ما يحتاج إلى متابعة اليوم.',
    ur: 'افراد، ان کی دستاویزات اور حاضری: آج کس پر توجہ درکار ہے۔',
    hi: 'लोग, उनके दस्तावेज़ और हाज़िरी: आज किस पर ध्यान चाहिए।',
  );
  static const people = TranslatableString(
    en: 'People',
    ar: 'الأفراد',
    ur: 'افراد',
    hi: 'लोग',
  );
  static const openPeople = TranslatableString(
    en: 'Open People',
    ar: 'فتح الأفراد',
    ur: 'افراد کھولیں',
    hi: 'लोग खोलें',
  );
  static const addPerson = TranslatableString(
    en: 'Add person',
    ar: 'إضافة شخص',
    ur: 'شخص شامل کریں',
    hi: 'व्यक्ति जोड़ें',
  );
  static const kpiPeopleSub = TranslatableString(
    en: '{s} staff · {l} labour',
    ar: '{s} موظفون · {l} عمال',
    ur: '{s} عملہ · {l} مزدور',
    hi: '{s} स्टाफ़ · {l} मज़दूर',
  );
  static const kpiExpiredDocs = TranslatableString(
    en: 'Expired documents',
    ar: 'مستندات منتهية',
    ur: 'ختم شدہ دستاویزات',
    hi: 'समाप्त दस्तावेज़',
  );
  static const kpiExpiredDocsSub = TranslatableString(
    en: 'People with an expired document',
    ar: 'أشخاص لديهم مستند منتهٍ',
    ur: 'جن کی کوئی دستاویز ختم ہو چکی',
    hi: 'जिनका कोई दस्तावेज़ समाप्त है',
  );
  static const kpiExpiringDocs = TranslatableString(
    en: 'Expiring soon',
    ar: 'تنتهي قريبًا',
    ur: 'جلد ختم',
    hi: 'जल्द समाप्त',
  );
  static const kpiExpiringDocsSub = TranslatableString(
    en: 'Within 60 days',
    ar: 'خلال 60 يومًا',
    ur: '60 دن کے اندر',
    hi: '60 दिनों में',
  );
  static const kpiCrewRequests = TranslatableString(
    en: 'Crew requests',
    ar: 'طلبات الطواقم',
    ur: 'عملے کی درخواستیں',
    hi: 'क्रू अनुरोध',
  );
  static const kpiCrewRequestsSub = TranslatableString(
    en: 'Waiting for you · {n} open',
    ar: 'بانتظارك · {n} مفتوحة',
    ur: 'آپ کے منتظر · {n} کھلی',
    hi: 'आपकी प्रतीक्षा में · {n} खुले',
  );
  static const documentsAttention = TranslatableString(
    en: 'Documents needing attention',
    ar: 'مستندات تحتاج إلى متابعة',
    ur: 'توجہ طلب دستاویزات',
    hi: 'ध्यान चाहने वाले दस्तावेज़',
  );
  static const documentsAttentionSub = TranslatableString(
    en: 'Expired first, then whatever ends in the next 60 days.',
    ar: 'المنتهية أولًا، ثم ما ينتهي خلال 60 يومًا.',
    ur: 'پہلے ختم شدہ، پھر جو اگلے 60 دن میں ختم ہوں۔',
    hi: 'पहले समाप्त, फिर जो अगले 60 दिनों में समाप्त हों।',
  );
  static const noDocumentsAttention = TranslatableString(
    en: 'No document has expired or expires in the next 60 days.',
    ar: 'لا يوجد مستند منتهٍ أو ينتهي خلال 60 يومًا.',
    ur: 'کوئی دستاویز ختم نہیں ہوئی اور نہ اگلے 60 دن میں ختم ہو رہی ہے۔',
    hi: 'कोई दस्तावेज़ समाप्त नहीं हुआ और न अगले 60 दिनों में होगा।',
  );
  static const moreOnPeople = TranslatableString(
    en: '{n} more on the People page.',
    ar: '{n} أخرى في صفحة الأفراد.',
    ur: 'افراد کے صفحے پر مزید {n}۔',
    hi: 'लोग पेज पर {n} और।',
  );
  static const crewRequests = TranslatableString(
    en: 'Crew requests',
    ar: 'طلبات الطواقم',
    ur: 'عملے کی درخواستیں',
    hi: 'क्रू अनुरोध',
  );
  static const crewRequestsSub = TranslatableString(
    en: 'Waiting for you first, then the rest still open.',
    ar: 'بانتظارك أولًا، ثم بقية المفتوحة.',
    ur: 'پہلے آپ کے منتظر، پھر باقی کھلی۔',
    hi: 'पहले आपकी प्रतीक्षा वाले, फिर बाकी खुले।',
  );
  static const noCrewRequests = TranslatableString(
    en: 'No crew request is open.',
    ar: 'لا يوجد طلب طاقم مفتوح.',
    ur: 'عملے کی کوئی درخواست کھلی نہیں۔',
    hi: 'कोई क्रू अनुरोध खुला नहीं।',
  );
  static const openWorkforce = TranslatableString(
    en: 'Open Workforce',
    ar: 'فتح القوى العاملة',
    ur: 'افرادی قوت کھولیں',
    hi: 'कार्यबल खोलें',
  );
  static const quickLinks = TranslatableString(
    en: 'Quick links',
    ar: 'روابط سريعة',
    ur: 'فوری روابط',
    hi: 'त्वरित लिंक',
  );
  static const peopleToolSub = TranslatableString(
    en: 'Staff, labour, documents and gate passes',
    ar: 'الموظفون والعمال والمستندات وتصاريح البوابات',
    ur: 'عملہ، مزدور، دستاویزات اور گیٹ پاس',
    hi: 'स्टाफ़, मज़दूर, दस्तावेज़ और गेट पास',
  );
  static const workforce = TranslatableString(
    en: 'Workforce',
    ar: 'القوى العاملة',
    ur: 'افرادی قوت',
    hi: 'कार्यबल',
  );
  static const workforceToolSub = TranslatableString(
    en: 'Attendance, monthly timesheets and the workforce month',
    ar: 'الحضور وكشوف الدوام الشهرية وشهر القوى العاملة',
    ur: 'حاضری، ماہانہ ٹائم شیٹس اور افرادی قوت کا مہینہ',
    hi: 'हाज़िरी, मासिक टाइमशीट और कार्यबल का महीना',
  );
  static const usersToolSub = TranslatableString(
    en: 'Logins, roles and worker records',
    ar: 'الحسابات والأدوار وسجلات العمال',
    ur: 'لاگ ان، کردار اور ورکر ریکارڈ',
    hi: 'लॉगिन, भूमिकाएँ और कर्मचारी रिकॉर्ड',
  );
  static const rentalsToolSub = TranslatableString(
    en: 'Units, leases, rent and cheques',
    ar: 'الوحدات والعقود والإيجار والشيكات',
    ur: 'یونٹس، لیز، کرایہ اور چیک',
    hi: 'यूनिट, लीज़, किराया और चेक',
  );

  static const companyAttention = TranslatableString(
    en: 'Company documents needing attention',
    ar: 'مستندات الشركة التي تحتاج إلى متابعة',
    ur: 'توجہ طلب کمپنی دستاویزات',
    hi: 'ध्यान चाहने वाले कंपनी दस्तावेज़',
  );
  static const companyAttentionSub = TranslatableString(
    en: 'Licences, vehicles, insurance and CICPA passes expired or ending within 60 days.',
    ar: 'الرخص والمركبات والتأمين وتصاريح CICPA المنتهية أو التي تنتهي خلال 60 يومًا.',
    ur: 'لائسنس، گاڑیاں، انشورنس اور CICPA پاسز جو ختم ہو چکے یا 60 دن میں ختم ہوں گے۔',
    hi: 'लाइसेंस, वाहन, बीमा और CICPA पास जो समाप्त हो चुके या 60 दिनों में समाप्त होंगे।',
  );
  static const noCompanyAttention = TranslatableString(
    en: 'No company document has expired or expires in the next 60 days.',
    ar: 'لا يوجد مستند للشركة منتهٍ أو ينتهي خلال 60 يومًا.',
    ur: 'کمپنی کی کوئی دستاویز ختم نہیں ہوئی اور نہ اگلے 60 دن میں ختم ہو رہی ہے۔',
    hi: 'कंपनी का कोई दस्तावेज़ समाप्त नहीं हुआ और न अगले 60 दिनों में होगा।',
  );
  static const companyDocuments = TranslatableString(
    en: 'Company documents',
    ar: 'مستندات الشركة',
    ur: 'کمپنی کی دستاویزات',
    hi: 'कंपनी दस्तावेज़',
  );
  static const openCompanyDocuments = TranslatableString(
    en: 'Open company documents',
    ar: 'فتح مستندات الشركة',
    ur: 'کمپنی دستاویزات کھولیں',
    hi: 'कंपनी दस्तावेज़ खोलें',
  );
  static const companyToolSub = TranslatableString(
    en: 'Licences, permits, vehicles, insurance and CICPA passes',
    ar: 'الرخص والتصاريح والمركبات والتأمين وتصاريح CICPA',
    ur: 'لائسنس، پرمٹ، گاڑیاں، انشورنس اور CICPA پاسز',
    hi: 'लाइसेंस, परमिट, वाहन, बीमा और CICPA पास',
  );
  static const moreOnCompany = TranslatableString(
    en: '{n} more in Company documents.',
    ar: '{n} أخرى في مستندات الشركة.',
    ur: 'کمپنی دستاویزات میں مزید {n}۔',
    hi: 'कंपनी दस्तावेज़ों में {n} और।',
  );

  // ─── Admin: rentals and activity ───────────────────────────────────────
  static const rentals = TranslatableString(
    en: 'Rentals',
    ar: 'الإيجارات',
    ur: 'کرائے',
    hi: 'किराये',
  );
  static const rentalsSub = TranslatableString(
    en: 'Aggregate only. Tenant details stay in Rental Properties.',
    ar: 'إجماليات فقط. تبقى بيانات المستأجرين في العقارات المؤجرة.',
    ur: 'صرف مجموعی۔ کرایہ داروں کی تفصیل کرائے کی جائیدادوں میں رہتی ہے۔',
    hi: 'केवल कुल योग। किरायेदार विवरण रेंटल प्रॉपर्टी में रहते हैं।',
  );
  static const rentalProperties = TranslatableString(
    en: 'Rental Properties',
    ar: 'العقارات المؤجرة',
    ur: 'کرائے کی جائیدادیں',
    hi: 'रेंटल प्रॉपर्टी',
  );
  static const occupied = TranslatableString(
    en: 'Occupied',
    ar: 'مشغولة',
    ur: 'زیر قبضہ',
    hi: 'भरी हुई',
  );
  static const unitsOf = TranslatableString(
    en: '{n} of {total} units',
    ar: '{n} من {total} وحدة',
    ur: '{total} میں سے {n} یونٹس',
    hi: '{total} में से {n} यूनिट',
  );
  static const collectedThisMonth = TranslatableString(
    en: 'Collected this month',
    ar: 'المحصّل هذا الشهر',
    ur: 'اس ماہ وصول شدہ',
    hi: 'इस महीने वसूला गया',
  );
  static const rentOutstanding = TranslatableString(
    en: 'Outstanding',
    ar: 'المستحق',
    ur: 'واجب الادا',
    hi: 'बकाया',
  );
  static const leasesExpiring = TranslatableString(
    en: 'Leases expiring in 90 days',
    ar: 'عقود تنتهي خلال 90 يومًا',
    ur: '90 دن میں ختم ہونے والے معاہدے',
    hi: '90 दिनों में समाप्त होने वाले पट्टे',
  );
  static const chequesNeedingAttention = TranslatableString(
    en: 'Cheques needing attention',
    ar: 'شيكات تحتاج اهتمامًا',
    ur: 'توجہ طلب چیک',
    hi: 'ध्यान देने योग्य चेक',
  );
  static const recentActivity = TranslatableString(
    en: 'Recent activity',
    ar: 'النشاط الأخير',
    ur: 'حالیہ سرگرمی',
    hi: 'हाल की गतिविधि',
  );
  static const recentActivitySub = TranslatableString(
    en: 'What changed, on which record, by whom.',
    ar: 'ما الذي تغيّر، وفي أي سجل، ومن قام به.',
    ur: 'کیا بدلا، کس ریکارڈ پر، کس نے۔',
    hi: 'क्या बदला, किस रिकॉर्ड पर, किसने।',
  );
  static const openAuditTrail = TranslatableString(
    en: 'Open audit trail',
    ar: 'فتح سجل التدقيق',
    ur: 'آڈٹ ٹریل کھولیں',
    hi: 'ऑडिट ट्रेल खोलें',
  );
  static const noRecentActivity = TranslatableString(
    en: 'No recorded activity yet.',
    ar: 'لا يوجد نشاط مسجل بعد.',
    ur: 'ابھی کوئی سرگرمی درج نہیں۔',
    hi: 'अभी कोई गतिविधि दर्ज नहीं।',
  );
}
