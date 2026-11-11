import 'app_strings.dart';

/// Copy for the User Management workspace (users, project teams and the
/// edit-user panel). Every string carries English plus the three configured
/// languages; the screen renders one language at a time.
abstract final class YorksV1UserManagementStrings {
  static const title = TranslatableString(
    en: 'User Management',
    ar: 'إدارة المستخدمين',
    ur: 'یوزر مینجمنٹ',
    hi: 'उपयोगकर्ता प्रबंधन',
  );
  static const description = TranslatableString(
    en: 'Accounts, roles, project teams and access for everyone at Yorks.',
    ar: 'الحسابات والأدوار وفرق المشاريع والصلاحيات لجميع العاملين في يوركس.',
    ur: 'یورکس میں سب کے اکاؤنٹس، رولز، پروجیکٹ ٹیمیں اور رسائی۔',
    hi: 'यॉर्क्स में सभी के खाते, भूमिकाएँ, परियोजना टीमें और पहुँच।',
  );
  static const refresh = TranslatableString(
    en: 'Refresh',
    ar: 'تحديث',
    ur: 'ریفریش',
    hi: 'रीफ़्रेश',
  );
  static const newUser = TranslatableString(
    en: 'New User',
    ar: 'مستخدم جديد',
    ur: 'نیا یوزر',
    hi: 'नया उपयोगकर्ता',
  );

  // Tabs ---------------------------------------------------------------------
  static const usersTab = TranslatableString(
    en: 'Users',
    ar: 'المستخدمون',
    ur: 'یوزرز',
    hi: 'उपयोगकर्ता',
  );
  static const projectAccessTab = TranslatableString(
    en: 'Project Access',
    ar: 'الوصول إلى المشاريع',
    ur: 'پروجیکٹ رسائی',
    hi: 'परियोजना पहुँच',
  );
  static const accessHistoryTab = TranslatableString(
    en: 'Access History',
    ar: 'سجل الصلاحيات',
    ur: 'رسائی کی تاریخ',
    hi: 'पहुँच इतिहास',
  );

  // Metrics ------------------------------------------------------------------
  static const totalAccounts = TranslatableString(
    en: 'Total accounts',
    ar: 'إجمالي الحسابات',
    ur: 'کل اکاؤنٹس',
    hi: 'कुल खाते',
  );
  static const allRolesHint = TranslatableString(
    en: 'Every role',
    ar: 'جميع الأدوار',
    ur: 'تمام رولز',
    hi: 'सभी भूमिकाएँ',
  );
  static const activeMetric = TranslatableString(
    en: 'Active',
    ar: 'نشط',
    ur: 'فعال',
    hi: 'सक्रिय',
  );
  static const canSignIn = TranslatableString(
    en: 'Can sign in',
    ar: 'يمكنه تسجيل الدخول',
    ur: 'سائن ان کر سکتے ہیں',
    hi: 'साइन इन कर सकते हैं',
  );
  static const engineersMetric = TranslatableString(
    en: 'Engineers',
    ar: 'المهندسون',
    ur: 'انجینئرز',
    hi: 'इंजीनियर',
  );
  static const engineersHint = TranslatableString(
    en: 'Project and site delivery',
    ar: 'تنفيذ المشاريع والمواقع',
    ur: 'پروجیکٹ اور سائٹ ڈیلیوری',
    hi: 'परियोजना और साइट डिलीवरी',
  );
  static const notOnProjectMetric = TranslatableString(
    en: 'Not on a project',
    ar: 'غير مكلف بمشروع',
    ur: 'کسی پروجیکٹ پر نہیں',
    hi: 'किसी परियोजना पर नहीं',
  );
  static const notOnProjectHint = TranslatableString(
    en: 'Engineers without a team',
    ar: 'مهندسون بلا فريق',
    ur: 'ٹیم کے بغیر انجینئرز',
    hi: 'बिना टीम के इंजीनियर',
  );
  static const projectsStaffedMetric = TranslatableString(
    en: 'Projects staffed',
    ar: 'مشاريع مزودة بفريق',
    ur: 'ٹیم والے پروجیکٹس',
    hi: 'टीम वाली परियोजनाएँ',
  );
  static const projectsStaffedHint = TranslatableString(
    en: 'Open projects with a Project Engineer',
    ar: 'مشاريع مفتوحة لديها مهندس مشروع',
    ur: 'پروجیکٹ انجینئر والے کھلے پروجیکٹس',
    hi: 'परियोजना इंजीनियर वाली खुली परियोजनाएँ',
  );
  static const deactivatedMetric = TranslatableString(
    en: 'Deactivated',
    ar: 'معطل',
    ur: 'غیر فعال',
    hi: 'निष्क्रिय',
  );
  static const historyRetained = TranslatableString(
    en: 'History retained',
    ar: 'السجل محفوظ',
    ur: 'ریکارڈ محفوظ',
    hi: 'इतिहास सुरक्षित',
  );

  // Users panel --------------------------------------------------------------
  static const searchUsers = TranslatableString(
    en: 'Search name, email, role or project...',
    ar: 'ابحث بالاسم أو البريد أو الدور أو المشروع...',
    ur: 'نام، ای میل، رول یا پروجیکٹ تلاش کریں...',
    hi: 'नाम, ईमेल, भूमिका या परियोजना खोजें...',
  );
  static const clearSearch = TranslatableString(
    en: 'Clear search',
    ar: 'مسح البحث',
    ur: 'تلاش صاف کریں',
    hi: 'खोज साफ़ करें',
  );
  static const allRoles = TranslatableString(
    en: 'All roles',
    ar: 'جميع الأدوار',
    ur: 'تمام رولز',
    hi: 'सभी भूमिकाएँ',
  );
  static const userColumn = TranslatableString(
    en: 'User',
    ar: 'المستخدم',
    ur: 'یوزر',
    hi: 'उपयोगकर्ता',
  );
  static const roleColumn = TranslatableString(
    en: 'Role',
    ar: 'الدور',
    ur: 'رول',
    hi: 'भूमिका',
  );
  static const projectAccessColumn = TranslatableString(
    en: 'Project access',
    ar: 'الوصول إلى المشاريع',
    ur: 'پروجیکٹ رسائی',
    hi: 'परियोजना पहुँच',
  );
  static const commercialColumn = TranslatableString(
    en: 'Commercial',
    ar: 'التجاري',
    ur: 'کمرشل',
    hi: 'वाणिज्यिक',
  );
  static const lastActiveColumn = TranslatableString(
    en: 'Last sign-in',
    ar: 'آخر دخول',
    ur: 'آخری سائن ان',
    hi: 'अंतिम साइन-इन',
  );
  static const statusColumn = TranslatableString(
    en: 'Status',
    ar: 'الحالة',
    ur: 'حالت',
    hi: 'स्थिति',
  );
  static const noUsersYet = TranslatableString(
    en: 'No accounts yet. Create the first user to get started.',
    ar: 'لا توجد حسابات بعد. أنشئ أول مستخدم للبدء.',
    ur: 'ابھی کوئی اکاؤنٹ نہیں۔ شروع کرنے کے لیے پہلا یوزر بنائیں۔',
    hi: 'अभी कोई खाता नहीं। शुरू करने के लिए पहला उपयोगकर्ता बनाएँ।',
  );
  static const noMatchingUsers = TranslatableString(
    en: 'No accounts match this view.',
    ar: 'لا توجد حسابات مطابقة لهذا العرض.',
    ur: 'اس منظر سے کوئی اکاؤنٹ نہیں ملتا۔',
    hi: 'इस दृश्य से कोई खाता मेल नहीं खाता।',
  );
  static const edit = TranslatableString(
    en: 'Edit',
    ar: 'تعديل',
    ur: 'ترمیم',
    hi: 'संपादित करें',
  );
  static const active = TranslatableString(
    en: 'Active',
    ar: 'نشط',
    ur: 'فعال',
    hi: 'सक्रिय',
  );
  static const deactivated = TranslatableString(
    en: 'Deactivated',
    ar: 'معطل',
    ur: 'غیر فعال',
    hi: 'निष्क्रिय',
  );

  // Project access summaries -------------------------------------------------
  static TranslatableString allProjects(int count) => TranslatableString(
    en: 'All projects · $count',
    ar: 'جميع المشاريع · $count',
    ur: 'تمام پروجیکٹس · $count',
    hi: 'सभी परियोजनाएँ · $count',
  );
  static TranslatableString activeProjects(int count) => TranslatableString(
    en: 'Active & on hold · $count',
    ar: 'نشطة ومعلقة · $count',
    ur: 'فعال اور روکے ہوئے · $count',
    hi: 'सक्रिय और रोकी गई · $count',
  );
  static TranslatableString projectsCount(int count) => TranslatableString(
    en: '$count ${count == 1 ? 'project' : 'projects'}',
    ar: '$count من المشاريع',
    ur: '$count پروجیکٹس',
    hi: '$count परियोजनाएँ',
  );
  static TranslatableString moreCount(int count) => TranslatableString(
    en: '+$count more',
    ar: '+$count أخرى',
    ur: '+$count مزید',
    hi: '+$count और',
  );
  static const notOnProject = TranslatableString(
    en: 'Not on a project',
    ar: 'غير مكلف بمشروع',
    ur: 'کسی پروجیکٹ پر نہیں',
    hi: 'किसी परियोजना पर नहीं',
  );
  static const noProjectAccess = TranslatableString(
    en: 'No project access',
    ar: 'لا وصول إلى المشاريع',
    ur: 'پروجیکٹ تک رسائی نہیں',
    hi: 'परियोजना पहुँच नहीं',
  );
  static const projectAccessLoading = TranslatableString(
    en: 'Loading...',
    ar: 'جارٍ التحميل...',
    ur: 'لوڈ ہو رہا ہے...',
    hi: 'लोड हो रहा है...',
  );
  static const projectAccessUnavailable = TranslatableString(
    en: 'Project access could not be loaded.',
    ar: 'تعذر تحميل الوصول إلى المشاريع.',
    ur: 'پروجیکٹ رسائی لوڈ نہیں ہو سکی۔',
    hi: 'परियोजना पहुँच लोड नहीं हो सकी।',
  );
  static const retry = TranslatableString(
    en: 'Try again',
    ar: 'حاول مرة أخرى',
    ur: 'دوبارہ کوشش کریں',
    hi: 'पुनः प्रयास करें',
  );

  // Commercial ---------------------------------------------------------------
  static const commercialManage = TranslatableString(
    en: 'View & manage',
    ar: 'عرض وإدارة',
    ur: 'دیکھیں اور منظم کریں',
    hi: 'देखें और प्रबंधित करें',
  );
  static const commercialView = TranslatableString(
    en: 'View',
    ar: 'عرض',
    ur: 'دیکھیں',
    hi: 'देखें',
  );
  static const commercialNone = TranslatableString(
    en: 'No access',
    ar: 'لا وصول',
    ur: 'رسائی نہیں',
    hi: 'पहुँच नहीं',
  );

  // Last sign-in -------------------------------------------------------------
  static const neverSignedIn = TranslatableString(
    en: 'Never',
    ar: 'أبدًا',
    ur: 'کبھی نہیں',
    hi: 'कभी नहीं',
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
  static TranslatableString daysAgo(int days) => TranslatableString(
    en: '$days days ago',
    ar: 'منذ $days أيام',
    ur: '$days دن پہلے',
    hi: '$days दिन पहले',
  );

  // Project Access tab -------------------------------------------------------
  static const projectTeams = TranslatableString(
    en: 'Project teams',
    ar: 'فرق المشاريع',
    ur: 'پروجیکٹ ٹیمیں',
    hi: 'परियोजना टीमें',
  );
  static const projectTeamsDescription = TranslatableString(
    en: 'Who works on each project. Project Engineers lead the project; Site Engineers cover it on site.',
    ar: 'من يعمل في كل مشروع. يقود مهندسو المشروع المشروع ويغطيه مهندسو الموقع ميدانيًا.',
    ur: 'ہر پروجیکٹ پر کون کام کرتا ہے۔ پروجیکٹ انجینئر قیادت کرتے ہیں؛ سائٹ انجینئر سائٹ پر کام دیکھتے ہیں۔',
    hi: 'हर परियोजना पर कौन काम करता है। परियोजना इंजीनियर नेतृत्व करते हैं; साइट इंजीनियर साइट पर काम संभालते हैं।',
  );
  static const accessRules = TranslatableString(
    en: 'Admin, Senior Mechanical Engineers, Project Managers, Workshop In-Charge and Document Controllers reach every project through their role. Procurement reaches active and on-hold projects. Project and Site Engineers reach only the projects they are assigned to here.',
    ar: 'يصل المسؤول وكبار المهندسين الميكانيكيين ومديرو المشاريع ومسؤولو الورشة ومراقبو الوثائق إلى كل مشروع من خلال أدوارهم. تصل المشتريات إلى المشاريع النشطة والمعلقة. ويصل مهندسو المشروع والموقع فقط إلى المشاريع المكلفين بها هنا.',
    ur: 'ایڈمن، سینئر مکینیکل انجینئر، پروجیکٹ مینیجر، ورکشاپ انچارج اور ڈاکیومنٹ کنٹرولر اپنے رول کے ذریعے ہر پروجیکٹ تک پہنچتے ہیں۔ پروکیورمنٹ فعال اور روکے ہوئے پروجیکٹس تک پہنچتی ہے۔ پروجیکٹ اور سائٹ انجینئر صرف یہاں تفویض کردہ پروجیکٹس تک پہنچتے ہیں۔',
    hi: 'एडमिन, सीनियर मैकेनिकल इंजीनियर, प्रोजेक्ट मैनेजर, वर्कशॉप इन-चार्ज और डॉक्यूमेंट कंट्रोलर अपनी भूमिका से हर परियोजना तक पहुँचते हैं। प्रोक्योरमेंट सक्रिय और रोकी गई परियोजनाओं तक पहुँचता है। परियोजना और साइट इंजीनियर केवल यहाँ सौंपी गई परियोजनाओं तक पहुँचते हैं।',
  );
  static const searchProjects = TranslatableString(
    en: 'Search project or engineer...',
    ar: 'ابحث عن مشروع أو مهندس...',
    ur: 'پروجیکٹ یا انجینئر تلاش کریں...',
    hi: 'परियोजना या इंजीनियर खोजें...',
  );
  static const openProjectsFilter = TranslatableString(
    en: 'Open projects',
    ar: 'المشاريع المفتوحة',
    ur: 'کھلے پروجیکٹس',
    hi: 'खुली परियोजनाएँ',
  );
  static const needsProjectEngineerFilter = TranslatableString(
    en: 'Needs a Project Engineer',
    ar: 'يحتاج مهندس مشروع',
    ur: 'پروجیکٹ انجینئر درکار',
    hi: 'परियोजना इंजीनियर चाहिए',
  );
  static const allProjectsFilter = TranslatableString(
    en: 'All projects',
    ar: 'جميع المشاريع',
    ur: 'تمام پروجیکٹس',
    hi: 'सभी परियोजनाएँ',
  );
  static const projectEngineers = TranslatableString(
    en: 'Project Engineers',
    ar: 'مهندسو المشروع',
    ur: 'پروجیکٹ انجینئرز',
    hi: 'परियोजना इंजीनियर',
  );
  static const siteEngineers = TranslatableString(
    en: 'Site Engineers',
    ar: 'مهندسو الموقع',
    ur: 'سائٹ انجینئرز',
    hi: 'साइट इंजीनियर',
  );
  static const noneAssigned = TranslatableString(
    en: 'None assigned',
    ar: 'لا أحد',
    ur: 'کوئی تفویض نہیں',
    hi: 'कोई नियुक्त नहीं',
  );
  static const manageTeam = TranslatableString(
    en: 'Manage team',
    ar: 'إدارة الفريق',
    ur: 'ٹیم منظم کریں',
    hi: 'टीम प्रबंधित करें',
  );
  static const viewOnly = TranslatableString(
    en: 'View only',
    ar: 'عرض فقط',
    ur: 'صرف دیکھنا',
    hi: 'केवल देखें',
  );
  static const organisationWide = TranslatableString(
    en: 'Organisation-wide access',
    ar: 'وصول على مستوى المؤسسة',
    ur: 'پوری تنظیم تک رسائی',
    hi: 'संगठन-व्यापी पहुँच',
  );
  static const organisationWideHint = TranslatableString(
    en: 'These accounts reach projects through their role, without a team assignment.',
    ar: 'تصل هذه الحسابات إلى المشاريع من خلال أدوارها دون تكليف بفريق.',
    ur: 'یہ اکاؤنٹس ٹیم تفویض کے بغیر اپنے رول کے ذریعے پروجیکٹس تک پہنچتے ہیں۔',
    hi: 'ये खाते टीम असाइनमेंट के बिना अपनी भूमिका से परियोजनाओं तक पहुँचते हैं।',
  );
  static const noProjects = TranslatableString(
    en: 'No projects match this view.',
    ar: 'لا توجد مشاريع مطابقة لهذا العرض.',
    ur: 'اس منظر سے کوئی پروجیکٹ نہیں ملتا۔',
    hi: 'इस दृश्य से कोई परियोजना मेल नहीं खाती।',
  );
  static const projectAccessOffline = TranslatableString(
    en: 'Project teams appear here when the workspace is connected.',
    ar: 'تظهر فرق المشاريع هنا عند اتصال مساحة العمل.',
    ur: 'ورک اسپیس کنیکٹ ہونے پر پروجیکٹ ٹیمیں یہاں نظر آتی ہیں۔',
    hi: 'वर्कस्पेस कनेक्ट होने पर परियोजना टीमें यहाँ दिखती हैं।',
  );
  static TranslatableString since(String date) => TranslatableString(
    en: 'Since $date',
    ar: 'منذ $date',
    ur: '$date سے',
    hi: '$date से',
  );
  static TranslatableString membersCount(int count) => TranslatableString(
    en: '$count ${count == 1 ? 'engineer' : 'engineers'}',
    ar: '$count من المهندسين',
    ur: '$count انجینئرز',
    hi: '$count इंजीनियर',
  );

  // Project states -----------------------------------------------------------
  static const stateDraft = TranslatableString(
    en: 'Draft',
    ar: 'مسودة',
    ur: 'مسودہ',
    hi: 'ड्राफ्ट',
  );
  static const stateActive = TranslatableString(
    en: 'Active',
    ar: 'نشط',
    ur: 'فعال',
    hi: 'सक्रिय',
  );
  static const stateOnHold = TranslatableString(
    en: 'On hold',
    ar: 'معلق',
    ur: 'روکا ہوا',
    hi: 'रोका गया',
  );
  static const stateCompleted = TranslatableString(
    en: 'Completed',
    ar: 'مكتمل',
    ur: 'مکمل',
    hi: 'पूर्ण',
  );
  static const stateArchived = TranslatableString(
    en: 'Archived',
    ar: 'مؤرشف',
    ur: 'آرکائیو',
    hi: 'संग्रहीत',
  );

  // Membership roles ---------------------------------------------------------
  static const projectEngineerRole = TranslatableString(
    en: 'Project Engineer',
    ar: 'مهندس مشروع',
    ur: 'پروجیکٹ انجینئر',
    hi: 'परियोजना इंजीनियर',
  );
  static const siteEngineerRole = TranslatableString(
    en: 'Site Engineer',
    ar: 'مهندس موقع',
    ur: 'سائٹ انجینئر',
    hi: 'साइट इंजीनियर',
  );
  static const notOnThisProject = TranslatableString(
    en: 'Not on this project',
    ar: 'ليس في هذا المشروع',
    ur: 'اس پروجیکٹ پر نہیں',
    hi: 'इस परियोजना पर नहीं',
  );

  // Team dialog --------------------------------------------------------------
  static TranslatableString manageTeamTitle(String reference) =>
      TranslatableString(
        en: 'Team · $reference',
        ar: 'الفريق · $reference',
        ur: 'ٹیم · $reference',
        hi: 'टीम · $reference',
      );
  static const teamDialogDescription = TranslatableString(
    en: 'Choose each engineer\'s role on this project. Every change is audited.',
    ar: 'اختر دور كل مهندس في هذا المشروع. يتم تدقيق كل تغيير.',
    ur: 'اس پروجیکٹ پر ہر انجینئر کا رول منتخب کریں۔ ہر تبدیلی آڈٹ ہوتی ہے۔',
    hi: 'इस परियोजना पर हर इंजीनियर की भूमिका चुनें। हर बदलाव ऑडिट होता है।',
  );
  static const onThisProject = TranslatableString(
    en: 'On this project',
    ar: 'في هذا المشروع',
    ur: 'اس پروجیکٹ پر',
    hi: 'इस परियोजना पर',
  );
  static const availableEngineers = TranslatableString(
    en: 'Available engineers',
    ar: 'المهندسون المتاحون',
    ur: 'دستیاب انجینئرز',
    hi: 'उपलब्ध इंजीनियर',
  );
  static const noEligibleEngineers = TranslatableString(
    en: 'No active Project or Site Engineers are available.',
    ar: 'لا يوجد مهندسو مشروع أو موقع نشطون متاحون.',
    ur: 'کوئی فعال پروجیکٹ یا سائٹ انجینئر دستیاب نہیں۔',
    hi: 'कोई सक्रिय परियोजना या साइट इंजीनियर उपलब्ध नहीं।',
  );
  static const changeReason = TranslatableString(
    en: 'Reason for the change',
    ar: 'سبب التغيير',
    ur: 'تبدیلی کی وجہ',
    hi: 'बदलाव का कारण',
  );
  static const changeReasonHint = TranslatableString(
    en: 'For example: assigned to the fit-out phase',
    ar: 'مثال: مكلف بمرحلة التشطيب',
    ur: 'مثال: فٹ آؤٹ مرحلے کے لیے تفویض',
    hi: 'उदाहरण: फिट-आउट चरण के लिए नियुक्त',
  );
  static const defaultReason = TranslatableString(
    en: 'Project access updated from User Management',
    ar: 'تم تحديث الوصول إلى المشروع من إدارة المستخدمين',
    ur: 'یوزر مینجمنٹ سے پروجیکٹ رسائی اپ ڈیٹ کی گئی',
    hi: 'उपयोगकर्ता प्रबंधन से परियोजना पहुँच अपडेट की गई',
  );
  static TranslatableString changesPending(int count) => TranslatableString(
    en: '$count ${count == 1 ? 'change' : 'changes'} to save',
    ar: '$count تغييرات للحفظ',
    ur: 'محفوظ کرنے کے لیے $count تبدیلیاں',
    hi: 'सहेजने के लिए $count बदलाव',
  );
  static const saveTeam = TranslatableString(
    en: 'Save team',
    ar: 'حفظ الفريق',
    ur: 'ٹیم محفوظ کریں',
    hi: 'टीम सहेजें',
  );
  static const cancel = TranslatableString(
    en: 'Cancel',
    ar: 'إلغاء',
    ur: 'منسوخ',
    hi: 'रद्द करें',
  );
  static const close = TranslatableString(
    en: 'Close',
    ar: 'إغلاق',
    ur: 'بند کریں',
    hi: 'बंद करें',
  );
  static const teamUpdated = TranslatableString(
    en: 'Project team updated.',
    ar: 'تم تحديث فريق المشروع.',
    ur: 'پروجیکٹ ٹیم اپ ڈیٹ ہو گئی۔',
    hi: 'परियोजना टीम अपडेट हुई।',
  );
  static const projectAccessUpdated = TranslatableString(
    en: 'Project access updated.',
    ar: 'تم تحديث الوصول إلى المشروع.',
    ur: 'پروجیکٹ رسائی اپ ڈیٹ ہو گئی۔',
    hi: 'परियोजना पहुँच अपडेट हुई।',
  );

  // Errors -------------------------------------------------------------------
  static const versionConflict = TranslatableString(
    en: 'This project changed while you were editing. The latest team is now shown; please review and try again.',
    ar: 'تغير هذا المشروع أثناء التعديل. يظهر الآن أحدث فريق؛ يرجى المراجعة والمحاولة مرة أخرى.',
    ur: 'ترمیم کے دوران یہ پروجیکٹ بدل گیا۔ تازہ ترین ٹیم دکھائی گئی ہے؛ دوبارہ دیکھ کر کوشش کریں۔',
    hi: 'संपादन के दौरान यह परियोजना बदल गई। नवीनतम टीम दिखाई गई है; जाँचकर पुनः प्रयास करें।',
  );
  static const needsProjectEngineerError = TranslatableString(
    en: 'An active project must keep at least one Project Engineer.',
    ar: 'يجب أن يحتفظ المشروع النشط بمهندس مشروع واحد على الأقل.',
    ur: 'فعال پروجیکٹ میں کم از کم ایک پروجیکٹ انجینئر ہونا ضروری ہے۔',
    hi: 'सक्रिय परियोजना में कम से कम एक परियोजना इंजीनियर होना चाहिए।',
  );
  static const notEligibleError = TranslatableString(
    en: 'Only active Project and Site Engineers can join a project team.',
    ar: 'يمكن فقط لمهندسي المشروع والموقع النشطين الانضمام إلى فريق المشروع.',
    ur: 'صرف فعال پروجیکٹ اور سائٹ انجینئر پروجیکٹ ٹیم میں شامل ہو سکتے ہیں۔',
    hi: 'केवल सक्रिय परियोजना और साइट इंजीनियर परियोजना टीम में शामिल हो सकते हैं।',
  );
  static const notAllowedError = TranslatableString(
    en: 'You can\'t change this project\'s team.',
    ar: 'لا يمكنك تغيير فريق هذا المشروع.',
    ur: 'آپ اس پروجیکٹ کی ٹیم تبدیل نہیں کر سکتے۔',
    hi: 'आप इस परियोजना की टीम नहीं बदल सकते।',
  );
  static const projectClosedError = TranslatableString(
    en: 'Completed and archived projects keep their final team.',
    ar: 'تحتفظ المشاريع المكتملة والمؤرشفة بفريقها النهائي.',
    ur: 'مکمل اور آرکائیو پروجیکٹس اپنی آخری ٹیم برقرار رکھتے ہیں۔',
    hi: 'पूर्ण और संग्रहीत परियोजनाएँ अपनी अंतिम टीम रखती हैं।',
  );
  static const teamChangeFailed = TranslatableString(
    en: 'The project team could not be updated. Check your connection and try again.',
    ar: 'تعذر تحديث فريق المشروع. تحقق من الاتصال وحاول مرة أخرى.',
    ur: 'پروجیکٹ ٹیم اپ ڈیٹ نہیں ہو سکی۔ کنکشن چیک کر کے دوبارہ کوشش کریں۔',
    hi: 'परियोजना टीम अपडेट नहीं हो सकी। कनेक्शन जाँचकर पुनः प्रयास करें।',
  );

  // Edit user panel ----------------------------------------------------------
  static const editUser = TranslatableString(
    en: 'Edit User',
    ar: 'تعديل المستخدم',
    ur: 'یوزر میں ترمیم',
    hi: 'उपयोगकर्ता संपादित करें',
  );
  static const createUser = TranslatableString(
    en: 'Create User',
    ar: 'إنشاء مستخدم',
    ur: 'یوزر بنائیں',
    hi: 'उपयोगकर्ता बनाएँ',
  );
  static const createUserDescription = TranslatableString(
    en: 'Accounts are created by management only. The person signs in with the email and initial password, then sets their own password.',
    ar: 'تنشئ الإدارة الحسابات فقط. يسجل الشخص الدخول بالبريد وكلمة المرور الأولية ثم يعيّن كلمة مروره.',
    ur: 'اکاؤنٹس صرف انتظامیہ بناتی ہے۔ صارف ای میل اور ابتدائی پاس ورڈ سے سائن ان کر کے اپنا پاس ورڈ سیٹ کرتا ہے۔',
    hi: 'खाते केवल प्रबंधन बनाता है। व्यक्ति ईमेल और प्रारंभिक पासवर्ड से साइन इन करके अपना पासवर्ड सेट करता है।',
  );
  static const accountSection = TranslatableString(
    en: 'Account',
    ar: 'الحساب',
    ur: 'اکاؤنٹ',
    hi: 'खाता',
  );
  static const accountSectionHint = TranslatableString(
    en: 'Sign-in status and the one role that sets what this person can do.',
    ar: 'حالة الدخول والدور الوحيد الذي يحدد ما يمكن لهذا الشخص فعله.',
    ur: 'سائن ان کی حالت اور وہ ایک رول جو طے کرتا ہے کہ یہ شخص کیا کر سکتا ہے۔',
    hi: 'साइन-इन स्थिति और वह एक भूमिका जो तय करती है कि यह व्यक्ति क्या कर सकता है।',
  );
  static const accountActive = TranslatableString(
    en: 'Account active',
    ar: 'الحساب نشط',
    ur: 'اکاؤنٹ فعال',
    hi: 'खाता सक्रिय',
  );
  static const accountActiveHint = TranslatableString(
    en: 'Turn off to block sign-in immediately. Records stay with this person.',
    ar: 'أوقفه لمنع الدخول فورًا. تبقى السجلات منسوبة لهذا الشخص.',
    ur: 'سائن ان فوراً روکنے کے لیے بند کریں۔ ریکارڈ اسی شخص کے نام رہتے ہیں۔',
    hi: 'साइन-इन तुरंत रोकने के लिए बंद करें। रिकॉर्ड इसी व्यक्ति के नाम रहते हैं।',
  );
  static const projectAccessSection = TranslatableString(
    en: 'Project access',
    ar: 'الوصول إلى المشاريع',
    ur: 'پروجیکٹ رسائی',
    hi: 'परियोजना पहुँच',
  );
  static TranslatableString allProjectsBasis(
    String role,
    int count,
  ) => TranslatableString(
    en: 'Reaches all $count projects through the $role role. No team assignment is needed.',
    ar: 'يصل إلى جميع المشاريع ($count) من خلال دور $role. لا حاجة لتكليف بفريق.',
    ur: '$role رول کے ذریعے تمام $count پروجیکٹس تک پہنچتا ہے۔ ٹیم تفویض کی ضرورت نہیں۔',
    hi: '$role भूमिका से सभी $count परियोजनाओं तक पहुँचता है। टीम असाइनमेंट की ज़रूरत नहीं।',
  );
  static TranslatableString activeProjectsBasis(
    int count,
  ) => TranslatableString(
    en: 'Reaches the $count active and on-hold projects through the Procurement role.',
    ar: 'يصل إلى المشاريع النشطة والمعلقة ($count) من خلال دور المشتريات.',
    ur: 'پروکیورمنٹ رول کے ذریعے $count فعال اور روکے ہوئے پروجیکٹس تک پہنچتا ہے۔',
    hi: 'प्रोक्योरमेंट भूमिका से $count सक्रिय और रोकी गई परियोजनाओं तक पहुँचता है।',
  );
  static const assignedBasis = TranslatableString(
    en: 'Works only on the projects below. Add a project or change the role on each one.',
    ar: 'يعمل فقط على المشاريع أدناه. أضف مشروعًا أو غيّر الدور في كل مشروع.',
    ur: 'صرف نیچے دیے گئے پروجیکٹس پر کام کرتا ہے۔ پروجیکٹ شامل کریں یا ہر ایک پر رول بدلیں۔',
    hi: 'केवल नीचे दी गई परियोजनाओं पर काम करता है। परियोजना जोड़ें या हर एक पर भूमिका बदलें।',
  );
  static const noneBasis = TranslatableString(
    en: 'This role does not open project records. Change the role to give project access.',
    ar: 'لا يفتح هذا الدور سجلات المشاريع. غيّر الدور لمنح الوصول إلى المشاريع.',
    ur: 'یہ رول پروجیکٹ ریکارڈ نہیں کھولتا۔ رسائی دینے کے لیے رول بدلیں۔',
    hi: 'यह भूमिका परियोजना रिकॉर्ड नहीं खोलती। पहुँच देने के लिए भूमिका बदलें।',
  );
  static const inactiveBasis = TranslatableString(
    en: 'A deactivated account cannot open any project. Its past assignments are kept.',
    ar: 'لا يمكن للحساب المعطل فتح أي مشروع. يتم الاحتفاظ بتكليفاته السابقة.',
    ur: 'غیر فعال اکاؤنٹ کوئی پروجیکٹ نہیں کھول سکتا۔ اس کی پچھلی تفویضات محفوظ ہیں۔',
    hi: 'निष्क्रिय खाता कोई परियोजना नहीं खोल सकता। इसके पिछले असाइनमेंट सुरक्षित हैं।',
  );
  static const notOnAnyProject = TranslatableString(
    en: 'Not on any project yet.',
    ar: 'غير مكلف بأي مشروع بعد.',
    ur: 'ابھی کسی پروجیکٹ پر نہیں۔',
    hi: 'अभी किसी परियोजना पर नहीं।',
  );
  static const addToProject = TranslatableString(
    en: 'Add to project',
    ar: 'إضافة إلى مشروع',
    ur: 'پروجیکٹ میں شامل کریں',
    hi: 'परियोजना में जोड़ें',
  );
  static const chooseProject = TranslatableString(
    en: 'Project',
    ar: 'المشروع',
    ur: 'پروجیکٹ',
    hi: 'परियोजना',
  );
  static const projectRole = TranslatableString(
    en: 'Role on the project',
    ar: 'الدور في المشروع',
    ur: 'پروجیکٹ پر رول',
    hi: 'परियोजना पर भूमिका',
  );
  static const addToProjectAction = TranslatableString(
    en: 'Add',
    ar: 'إضافة',
    ur: 'شامل کریں',
    hi: 'जोड़ें',
  );
  static const noProjectsToAdd = TranslatableString(
    en: 'This person is already on every project you can manage.',
    ar: 'هذا الشخص موجود بالفعل في كل مشروع يمكنك إدارته.',
    ur: 'یہ شخص پہلے ہی ہر اس پروجیکٹ پر ہے جسے آپ منظم کر سکتے ہیں۔',
    hi: 'यह व्यक्ति पहले से हर उस परियोजना पर है जिसे आप प्रबंधित कर सकते हैं।',
  );
  static const removeFromProject = TranslatableString(
    en: 'Remove from project',
    ar: 'إزالة من المشروع',
    ur: 'پروجیکٹ سے ہٹائیں',
    hi: 'परियोजना से हटाएँ',
  );
  static const openProject = TranslatableString(
    en: 'Open project',
    ar: 'فتح المشروع',
    ur: 'پروجیکٹ کھولیں',
    hi: 'परियोजना खोलें',
  );
  static const commercialSection = TranslatableString(
    en: 'Commercial access',
    ar: 'الوصول التجاري',
    ur: 'کمرشل رسائی',
    hi: 'वाणिज्यिक पहुँच',
  );
  static const hrSection = TranslatableString(
    en: 'HR employee record',
    ar: 'سجل الموظف',
    ur: 'ایچ آر ملازم ریکارڈ',
    hi: 'एचआर कर्मचारी रिकॉर्ड',
  );
  static const hrNotLinked = TranslatableString(
    en: 'Not linked',
    ar: 'غير مرتبط',
    ur: 'منسلک نہیں',
    hi: 'लिंक नहीं',
  );
  static const hrNotLinkedHint = TranslatableString(
    en: 'Link the HR record so this person can request leave and see their balance.',
    ar: 'اربط سجل الموظف ليتمكن هذا الشخص من طلب الإجازة ورؤية رصيده.',
    ur: 'ایچ آر ریکارڈ منسلک کریں تاکہ یہ شخص چھٹی کی درخواست اور بیلنس دیکھ سکے۔',
    hi: 'एचआर रिकॉर्ड लिंक करें ताकि यह व्यक्ति छुट्टी माँग सके और बैलेंस देख सके।',
  );
  static const link = TranslatableString(
    en: 'Link',
    ar: 'ربط',
    ur: 'منسلک کریں',
    hi: 'लिंक करें',
  );
  static const change = TranslatableString(
    en: 'Change',
    ar: 'تغيير',
    ur: 'تبدیل کریں',
    hi: 'बदलें',
  );
  static const securitySection = TranslatableString(
    en: 'Sign-in and permissions',
    ar: 'الدخول والصلاحيات',
    ur: 'سائن ان اور اجازتیں',
    hi: 'साइन-इन और अनुमतियाँ',
  );
  static const resetPasswordHint = TranslatableString(
    en: 'Issue a temporary password. The person must set a new one at next sign-in.',
    ar: 'أصدر كلمة مرور مؤقتة. يجب على الشخص تعيين كلمة جديدة عند الدخول التالي.',
    ur: 'عارضی پاس ورڈ جاری کریں۔ اگلے سائن ان پر نیا پاس ورڈ لازمی ہوگا۔',
    hi: 'अस्थायी पासवर्ड जारी करें। अगले साइन-इन पर नया पासवर्ड ज़रूरी होगा।',
  );
  static const detailedPermissions = TranslatableString(
    en: 'Detailed permissions',
    ar: 'الصلاحيات التفصيلية',
    ur: 'تفصیلی اجازتیں',
    hi: 'विस्तृत अनुमतियाँ',
  );
  static const detailedPermissionsHint = TranslatableString(
    en: 'Grant or restrict individual capabilities, with history.',
    ar: 'امنح أو قيّد قدرات فردية مع السجل.',
    ur: 'تاریخ کے ساتھ انفرادی صلاحیتیں دیں یا محدود کریں۔',
    hi: 'इतिहास के साथ अलग-अलग क्षमताएँ दें या सीमित करें।',
  );
  static const accountRemovalSection = TranslatableString(
    en: 'Account removal',
    ar: 'إزالة الحساب',
    ur: 'اکاؤنٹ ہٹانا',
    hi: 'खाता हटाना',
  );
  static const accountRemovalHint = TranslatableString(
    en: 'Access stops immediately. Records stay attributed to this person and the account can be restored.',
    ar: 'يتوقف الوصول فورًا. تبقى السجلات منسوبة لهذا الشخص ويمكن استعادة الحساب.',
    ur: 'رسائی فوراً رک جاتی ہے۔ ریکارڈ اسی شخص کے نام رہتے ہیں اور اکاؤنٹ بحال ہو سکتا ہے۔',
    hi: 'पहुँच तुरंत रुकती है। रिकॉर्ड इसी व्यक्ति के नाम रहते हैं और खाता बहाल हो सकता है।',
  );
  static const legacyPermissionsSection = TranslatableString(
    en: 'Module permissions',
    ar: 'صلاحيات الوحدات',
    ur: 'ماڈیول اجازتیں',
    hi: 'मॉड्यूल अनुमतियाँ',
  );
  static const legacyPermissionsHint = TranslatableString(
    en: 'Override what this person can open. Each switch follows the role until you change it.',
    ar: 'تجاوز ما يمكن لهذا الشخص فتحه. يتبع كل مفتاح الدور حتى تغيّره.',
    ur: 'یہ شخص کیا کھول سکتا ہے اسے تبدیل کریں۔ ہر سوئچ رول کے مطابق رہتا ہے جب تک آپ نہ بدلیں۔',
    hi: 'यह व्यक्ति क्या खोल सकता है उसे बदलें। हर स्विच भूमिका के अनुसार रहता है जब तक आप न बदलें।',
  );
  static const roleDefault = TranslatableString(
    en: 'Role default',
    ar: 'افتراضي الدور',
    ur: 'رول ڈیفالٹ',
    hi: 'भूमिका डिफ़ॉल्ट',
  );
  static const customForUser = TranslatableString(
    en: 'Custom for this person',
    ar: 'مخصص لهذا الشخص',
    ur: 'اس شخص کے لیے مخصوص',
    hi: 'इस व्यक्ति के लिए विशेष',
  );
  static const youLabel = TranslatableString(
    en: 'You',
    ar: 'أنت',
    ur: 'آپ',
    hi: 'आप',
  );

  // Access history -----------------------------------------------------------
  static const accessHistory = TranslatableString(
    en: 'Access history',
    ar: 'سجل الصلاحيات',
    ur: 'رسائی کی تاریخ',
    hi: 'पहुँच इतिहास',
  );
  static const accessHistoryDescription = TranslatableString(
    en: 'Account creation, role changes, deactivation and restoration made on this device.',
    ar: 'إنشاء الحسابات وتغييرات الأدوار والتعطيل والاستعادة على هذا الجهاز.',
    ur: 'اس ڈیوائس پر اکاؤنٹ بنانا، رول تبدیلیاں، غیر فعال اور بحال کرنا۔',
    hi: 'इस डिवाइस पर खाता बनाना, भूमिका बदलाव, निष्क्रिय और बहाल करना।',
  );
  static const noAccessHistory = TranslatableString(
    en: 'No access changes recorded yet.',
    ar: 'لم تسجل تغييرات في الصلاحيات بعد.',
    ur: 'ابھی کوئی رسائی تبدیلی ریکارڈ نہیں ہوئی۔',
    hi: 'अभी कोई पहुँच बदलाव दर्ज नहीं हुआ।',
  );
  static const fullAuditTrail = TranslatableString(
    en: 'Open audit trail',
    ar: 'فتح سجل التدقيق',
    ur: 'آڈٹ ٹریل کھولیں',
    hi: 'ऑडिट ट्रेल खोलें',
  );
}
