import 'app_language.dart';
import 'app_strings.dart';
import 'yorks_v1_role.dart';

/// Copy used by the canonical My Yorks page.
///
/// Keeping the catalogue beside the profile contract makes every visible and
/// semantic label available to all four supported languages without coupling
/// the responsive widgets to a particular role or data source.
abstract final class YorksV1ProfileStrings {
  static const organizationName = TranslatableString(
    en: 'Yorks AC. & Ref.',
    ar: 'Yorks AC. & Ref.',
    ur: 'Yorks AC. & Ref.',
    hi: 'Yorks AC. & Ref.',
  );
  static const introduction = TranslatableString(
    en: 'Your verified Yorks account, preferences and security in one place.',
    ar: 'حساب يوركس الموثق وتفضيلاتك وأمانك في مكان واحد.',
    ur: 'آپ کا تصدیق شدہ یورکس اکاؤنٹ، ترجیحات اور سیکیورٹی ایک جگہ۔',
    hi: 'आपका सत्यापित यॉर्क्स खाता, प्राथमिकताएं और सुरक्षा एक ही स्थान पर।',
  );
  static const account = TranslatableString(
    en: 'Account',
    ar: 'الحساب',
    ur: 'اکاؤنٹ',
    hi: 'खाता',
  );
  static const today = TranslatableString(
    en: 'Today',
    ar: 'اليوم',
    ur: 'آج',
    hi: 'आज',
  );
  static const todayDescription = TranslatableString(
    en: 'A small, server-confirmed view of the workspaces and follow-up that matter to you.',
    ar: 'عرض صغير مؤكد من الخادم لمساحات العمل والمتابعة المهمة لك.',
    ur: 'آپ کے لیے اہم ورک اسپیس اور فالو اَپ کا مختصر، سرور سے تصدیق شدہ منظر۔',
    hi: 'आपके लिए महत्वपूर्ण कार्यस्थलों और फॉलो-अप का छोटा, सर्वर-पुष्ट दृश्य।',
  );
  static const accessAndScope = TranslatableString(
    en: 'Access & scope',
    ar: 'الوصول والنطاق',
    ur: 'رسائی اور دائرہ',
    hi: 'पहुंच और दायरा',
  );
  static const accessAndScopeDescription = TranslatableString(
    en: 'See the confirmed reach of your Yorks account and where that access comes from.',
    ar: 'اعرض نطاق حساب يوركس المؤكد ومصدر هذه الصلاحية.',
    ur: 'اپنے یورکس اکاؤنٹ کی تصدیق شدہ رسائی اور اس رسائی کا ذریعہ دیکھیں۔',
    hi: 'अपने यॉर्क्स खाते की पुष्टि की गई पहुंच और उसका स्रोत देखें।',
  );
  static const workIdentity = TranslatableString(
    en: 'Work identity',
    ar: 'هوية العمل',
    ur: 'کام کی شناخت',
    hi: 'कार्य पहचान',
  );
  static const workIdentityDescription = TranslatableString(
    en: 'A separate Workforce record can identify your work profile without changing account access.',
    ar: 'يمكن لسجل القوى العاملة المنفصل تعريف ملف عملك دون تغيير صلاحية الحساب.',
    ur: 'ایک الگ ورک فورس ریکارڈ آپ کے ورک پروفائل کی شناخت کر سکتا ہے، مگر اکاؤنٹ رسائی نہیں بدلتا۔',
    hi: 'एक अलग कार्यबल रिकॉर्ड आपके कार्य प्रोफ़ाइल की पहचान कर सकता है, लेकिन खाता पहुंच नहीं बदलता।',
  );
  static const quickActions = TranslatableString(
    en: 'Quick actions',
    ar: 'إجراءات سريعة',
    ur: 'فوری اقدامات',
    hi: 'त्वरित कार्य',
  );
  static const quickActionsDescription = TranslatableString(
    en: 'Only workspaces Yorks currently confirms for your account are shown here.',
    ar: 'تظهر هنا فقط مساحات العمل التي يؤكدها يوركس حالياً لحسابك.',
    ur: 'یہاں صرف وہ ورک اسپیس دکھائی جاتی ہیں جن کی یورکس اس وقت آپ کے اکاؤنٹ کے لیے تصدیق کرتا ہے۔',
    hi: 'यहां केवल वे कार्यस्थल दिखाए जाते हैं जिनकी यॉर्क्स इस समय आपके खाते के लिए पुष्टि करता है।',
  );
  static const preferences = TranslatableString(
    en: 'Preferences',
    ar: 'التفضيلات',
    ur: 'ترجیحات',
    hi: 'प्राथमिकताएं',
  );
  static const preferencesDescription = TranslatableString(
    en: 'Choose how Yorks appears and alerts you on this device.',
    ar: 'اختر طريقة عرض يوركس وتنبيهك على هذا الجهاز.',
    ur: 'اس ڈیوائس پر یورکس کی ظاہری شکل اور اطلاعات منتخب کریں۔',
    hi: 'इस डिवाइस पर यॉर्क्स का रूप और सूचनाएं चुनें।',
  );
  static const helpAndSecurity = TranslatableString(
    en: 'Help & security',
    ar: 'المساعدة والأمان',
    ur: 'مدد اور سیکیورٹی',
    hi: 'सहायता और सुरक्षा',
  );
  static const helpAndSecurityDescription = TranslatableString(
    en: 'Check connection details, app information and your session.',
    ar: 'تحقق من تفاصيل الاتصال ومعلومات التطبيق وجلستك.',
    ur: 'کنکشن کی تفصیل، ایپ کی معلومات اور اپنا سیشن دیکھیں۔',
    hi: 'कनेक्शन विवरण, ऐप की जानकारी और अपना सत्र देखें।',
  );
  static const sectionNavigation = TranslatableString(
    en: 'My Yorks sections',
    ar: 'أقسام يوركس الخاصة بي',
    ur: 'میرا یورکس حصے',
    hi: 'मेरा यॉर्क्स अनुभाग',
  );
  static const verifiedAccount = TranslatableString(
    en: 'Verified account',
    ar: 'حساب موثق',
    ur: 'تصدیق شدہ اکاؤنٹ',
    hi: 'सत्यापित खाता',
  );
  static const verifiedByYorks = TranslatableString(
    en: 'Confirmed by the protected Yorks account service.',
    ar: 'تم التأكيد بواسطة خدمة حساب يوركس المحمية.',
    ur: 'محفوظ یورکس اکاؤنٹ سروس سے تصدیق شدہ۔',
    hi: 'सुरक्षित यॉर्क्स खाता सेवा द्वारा पुष्टि की गई।',
  );
  static const verifyingAccount = TranslatableString(
    en: 'Verifying your account',
    ar: 'جارٍ التحقق من حسابك',
    ur: 'آپ کے اکاؤنٹ کی تصدیق ہو رہی ہے',
    hi: 'आपके खाते की पुष्टि की जा रही है',
  );
  static const verifyingAccountDescription = TranslatableString(
    en: 'Waiting for the protected server response. No access is assumed.',
    ar: 'في انتظار استجابة الخادم المحمية. لا يتم افتراض أي صلاحية.',
    ur: 'محفوظ سرور کے جواب کا انتظار ہے۔ کسی رسائی کو فرض نہیں کیا گیا۔',
    hi: 'सुरक्षित सर्वर के उत्तर की प्रतीक्षा है। कोई पहुंच मान नहीं ली गई है।',
  );
  static const accountUnavailable = TranslatableString(
    en: 'Account details are unavailable',
    ar: 'تفاصيل الحساب غير متاحة',
    ur: 'اکاؤنٹ کی تفصیلات دستیاب نہیں ہیں',
    hi: 'खाते का विवरण उपलब्ध नहीं है',
  );
  static const accountUnavailableDescription = TranslatableString(
    en: 'Yorks could not confirm this account. Check the connection and try again.',
    ar: 'تعذر على يوركس تأكيد هذا الحساب. تحقق من الاتصال وحاول مرة أخرى.',
    ur: 'یورکس اس اکاؤنٹ کی تصدیق نہیں کر سکا۔ کنکشن دیکھیں اور دوبارہ کوشش کریں۔',
    hi: 'यॉर्क्स इस खाते की पुष्टि नहीं कर सका। कनेक्शन जांचें और फिर प्रयास करें।',
  );
  static const tryAgain = TranslatableString(
    en: 'Try again',
    ar: 'حاول مرة أخرى',
    ur: 'دوبارہ کوشش کریں',
    hi: 'फिर प्रयास करें',
  );
  static const signedInEmail = TranslatableString(
    en: 'Signed-in email',
    ar: 'البريد الإلكتروني المسجل',
    ur: 'سائن ان ای میل',
    hi: 'साइन-इन ईमेल',
  );
  static const exactAccountRole = TranslatableString(
    en: 'Account role',
    ar: 'دور الحساب',
    ur: 'اکاؤنٹ کا کردار',
    hi: 'खाता भूमिका',
  );
  static const active = TranslatableString(
    en: 'Active',
    ar: 'نشط',
    ur: 'فعال',
    hi: 'सक्रिय',
  );
  static const notificationsDescription = TranslatableString(
    en: 'Choose push, workflow, Team Chat, pop-up and sound preferences.',
    ar: 'اختر تفضيلات الإشعارات الفورية وسير العمل ومحادثة الفريق والنوافذ المنبثقة والصوت.',
    ur: 'پش، ورک فلو، ٹیم چیٹ، پاپ اپ اور آواز کی ترجیحات منتخب کریں۔',
    hi: 'पुश, कार्यप्रवाह, टीम चैट, पॉप-अप और ध्वनि प्राथमिकताएं चुनें।',
  );
  static const chooseLanguage = TranslatableString(
    en: 'Choose the language used by Yorks.',
    ar: 'اختر اللغة المستخدمة في يوركس.',
    ur: 'یورکس میں استعمال ہونے والی زبان منتخب کریں۔',
    hi: 'यॉर्क्स में उपयोग की जाने वाली भाषा चुनें।',
  );
  static const chooseCurrency = TranslatableString(
    en: 'Yorks uses AED as its fixed company reporting currency.',
    ar: 'يستخدم يوركس الدرهم الإماراتي كعملة ثابتة لتقارير الشركة.',
    ur: 'یورکس کمپنی رپورٹنگ کے لیے AED کو مقررہ کرنسی کے طور پر استعمال کرتا ہے۔',
    hi: 'यॉर्क्स कंपनी रिपोर्टिंग के लिए AED को निश्चित मुद्रा के रूप में उपयोग करता है।',
  );
  static const enabled = TranslatableString(
    en: 'Enabled',
    ar: 'مفعّل',
    ur: 'فعال',
    hi: 'चालू',
  );
  static const disabled = TranslatableString(
    en: 'Disabled',
    ar: 'معطّل',
    ur: 'غیر فعال',
    hi: 'बंद',
  );
  static const appLockDescription = TranslatableString(
    en: 'Require device authentication when Yorks is reopened.',
    ar: 'اطلب مصادقة الجهاز عند إعادة فتح يوركس.',
    ur: 'یورکس دوبارہ کھولنے پر ڈیوائس کی تصدیق درکار ہو۔',
    hi: 'यॉर्क्स दोबारा खोलने पर डिवाइस प्रमाणीकरण आवश्यक करें।',
  );
  static const workspaceSyncDescription = TranslatableString(
    en: 'View connectivity, queued changes and retry status.',
    ar: 'اعرض الاتصال والتغييرات المنتظرة وحالة إعادة المحاولة.',
    ur: 'کنکشن، قطار میں تبدیلیاں اور دوبارہ کوشش کی حالت دیکھیں۔',
    hi: 'कनेक्टिविटी, कतारबद्ध बदलाव और पुनः प्रयास की स्थिति देखें।',
  );
  static const aboutDescription = TranslatableString(
    en: 'Yorks version, privacy and product information.',
    ar: 'إصدار يوركس والخصوصية ومعلومات المنتج.',
    ur: 'یورکس ورژن، رازداری اور پروڈکٹ کی معلومات۔',
    hi: 'यॉर्क्स संस्करण, गोपनीयता और उत्पाद जानकारी।',
  );
  static const contactSupport = TranslatableString(
    en: 'Contact support',
    ar: 'التواصل مع الدعم',
    ur: 'سپورٹ سے رابطہ کریں',
    hi: 'सहायता से संपर्क करें',
  );
  static const contactSupportDescription = TranslatableString(
    en: 'Open the company support conversation in WhatsApp.',
    ar: 'افتح محادثة دعم الشركة في واتساب.',
    ur: 'کمپنی سپورٹ کی گفتگو واٹس ایپ میں کھولیں۔',
    hi: 'कंपनी सहायता बातचीत WhatsApp में खोलें।',
  );
  static const supportMessage = TranslatableString(
    en: 'Hello, I need help with the Yorks app.',
    ar: 'مرحباً، أحتاج إلى مساعدة في تطبيق يوركس.',
    ur: 'السلام علیکم، مجھے یورکس ایپ کے بارے میں مدد چاہیے۔',
    hi: 'नमस्ते, मुझे यॉर्क्स ऐप में सहायता चाहिए।',
  );
  static const supportCopied = TranslatableString(
    en: 'Support number copied',
    ar: 'تم نسخ رقم الدعم',
    ur: 'سپورٹ نمبر کاپی ہو گیا',
    hi: 'सहायता नंबर कॉपी हो गया',
  );
  static const signOutDescription = TranslatableString(
    en: 'End this Yorks session on this device.',
    ar: 'أنهِ جلسة يوركس هذه على هذا الجهاز.',
    ur: 'اس ڈیوائس پر یہ یورکس سیشن ختم کریں۔',
    hi: 'इस डिवाइस पर यह यॉर्क्स सत्र समाप्त करें।',
  );
  static const syncStatus = TranslatableString(
    en: 'Sync status',
    ar: 'حالة المزامنة',
    ur: 'سنک کی حالت',
    hi: 'सिंक स्थिति',
  );
  static const offlineWorkspace = TranslatableString(
    en: 'Offline workspace',
    ar: 'مساحة العمل غير متصلة',
    ur: 'آف لائن ورک اسپیس',
    hi: 'ऑफलाइन कार्यक्षेत्र',
  );
  static const syncingChanges = TranslatableString(
    en: 'Syncing changes',
    ar: 'جارٍ مزامنة التغييرات',
    ur: 'تبدیلیاں سنک ہو رہی ہیں',
    hi: 'बदलाव सिंक हो रहे हैं',
  );
  static const changesNeedAttention = TranslatableString(
    en: 'Changes need attention',
    ar: 'تحتاج التغييرات إلى انتباه',
    ur: 'تبدیلیوں پر توجہ درکار ہے',
    hi: 'बदलावों पर ध्यान देना आवश्यक है',
  );
  static const workspaceConnected = TranslatableString(
    en: 'Workspace connected',
    ar: 'مساحة العمل متصلة',
    ur: 'ورک اسپیس منسلک ہے',
    hi: 'कार्यस्थल जुड़ा हुआ है',
  );
  static const workspaceStatusUnavailable = TranslatableString(
    en: 'Workspace status unavailable',
    ar: 'حالة مساحة العمل غير متاحة',
    ur: 'ورک اسپیس کی حالت دستیاب نہیں',
    hi: 'कार्यस्थल की स्थिति उपलब्ध नहीं है',
  );
  static const localDraftsOffline = TranslatableString(
    en: 'You can keep local drafts. Connected commands wait for the server.',
    ar: 'يمكنك الاحتفاظ بالمسودات المحلية. تنتظر الأوامر المتصلة الخادم.',
    ur: 'آپ مقامی ڈرافٹس رکھ سکتے ہیں۔ منسلک کمانڈز سرور کا انتظار کرتی ہیں۔',
    hi: 'आप स्थानीय ड्राफ्ट रख सकते हैं। कनेक्टेड कमांड सर्वर की प्रतीक्षा करते हैं।',
  );
  static const noQueuedChanges = TranslatableString(
    en: 'No queued changes need your attention.',
    ar: 'لا توجد تغييرات منتظرة تحتاج إلى انتباهك.',
    ur: 'قطار میں کوئی تبدیلی آپ کی توجہ نہیں چاہتی۔',
    hi: 'कतार में किसी बदलाव को आपके ध्यान की आवश्यकता नहीं है।',
  );
  static const connectionWillUpdate = TranslatableString(
    en: 'The connection status will update when it can be confirmed.',
    ar: 'سيتم تحديث حالة الاتصال عند تأكيدها.',
    ur: 'کنکشن کی تصدیق ہونے پر اس کی حالت اپ ڈیٹ ہو جائے گی۔',
    hi: 'पुष्टि होने पर कनेक्शन की स्थिति अपडेट हो जाएगी।',
  );
  static const conflictHandling = TranslatableString(
    en: 'Conflict handling',
    ar: 'معالجة التعارض',
    ur: 'تنازع کا انتظام',
    hi: 'टकराव प्रबंधन',
  );
  static const conflictHandlingDescription = TranslatableString(
    en: 'If a server version changes while you edit a record, that record stays open and shows both versions for review. It is never silently overwritten from this global panel.',
    ar: 'إذا تغير إصدار الخادم أثناء تعديل سجل، يبقى السجل مفتوحاً ويعرض الإصدارين للمراجعة. لا تتم الكتابة فوقه بصمت من هذه اللوحة العامة.',
    ur: 'اگر ریکارڈ میں ترمیم کے دوران سرور ورژن بدل جائے تو ریکارڈ کھلا رہتا ہے اور جائزے کے لیے دونوں ورژن دکھاتا ہے۔ اس عمومی پینل سے اسے خاموشی سے اوور رائٹ نہیں کیا جاتا۔',
    hi: 'यदि रिकॉर्ड संपादित करते समय सर्वर संस्करण बदलता है, तो रिकॉर्ड खुला रहता है और समीक्षा के लिए दोनों संस्करण दिखाता है। इस वैश्विक पैनल से इसे चुपचाप ओवरराइट नहीं किया जाता।',
  );
  static const retrySync = TranslatableString(
    en: 'Retry sync',
    ar: 'أعد محاولة المزامنة',
    ur: 'سنک دوبارہ کریں',
    hi: 'सिंक फिर प्रयास करें',
  );
  static const accountCardSemantic = TranslatableString(
    en: 'Verified Yorks account identity',
    ar: 'هوية حساب يوركس الموثقة',
    ur: 'تصدیق شدہ یورکس اکاؤنٹ شناخت',
    hi: 'सत्यापित यॉर्क्स खाता पहचान',
  );
  static const workspaceFactsLoading = TranslatableString(
    en: 'Loading your confirmed workspace',
    ar: 'جارٍ تحميل مساحة العمل المؤكدة',
    ur: 'آپ کی تصدیق شدہ ورک اسپیس لوڈ ہو رہی ہے',
    hi: 'आपका पुष्टि किया गया कार्यस्थल लोड हो रहा है',
  );
  static const workspaceFactsLoadingDescription = TranslatableString(
    en: 'Yorks is checking your current scope. No work count or action is assumed.',
    ar: 'يتحقق يوركس من نطاقك الحالي. لا يتم افتراض أي عدد عمل أو إجراء.',
    ur: 'یورکس آپ کے موجودہ دائرے کی جانچ کر رہا ہے۔ کوئی کام کی گنتی یا کارروائی فرض نہیں کی گئی۔',
    hi: 'यॉर्क्स आपके वर्तमान दायरे की जांच कर रहा है। कोई कार्य गणना या कार्रवाई मान नहीं ली गई है।',
  );
  static const workspaceFactsUnavailable = TranslatableString(
    en: 'Your workspace details are unavailable',
    ar: 'تفاصيل مساحة عملك غير متاحة',
    ur: 'آپ کی ورک اسپیس کی تفصیلات دستیاب نہیں ہیں',
    hi: 'आपके कार्यस्थल का विवरण उपलब्ध नहीं है',
  );
  static const workspaceFactsUnavailableDescription = TranslatableString(
    en: 'Yorks could not confirm your current workspace details. Try again before relying on these cards.',
    ar: 'تعذر على يوركس تأكيد تفاصيل مساحة عملك الحالية. حاول مرة أخرى قبل الاعتماد على هذه البطاقات.',
    ur: 'یورکس آپ کی موجودہ ورک اسپیس کی تفصیلات کی تصدیق نہیں کر سکا۔ ان کارڈز پر انحصار سے پہلے دوبارہ کوشش کریں۔',
    hi: 'यॉर्क्स आपके वर्तमान कार्यस्थल के विवरण की पुष्टि नहीं कर सका। इन कार्डों पर भरोसा करने से पहले फिर प्रयास करें।',
  );
  static const noTodayFacts = TranslatableString(
    en: 'No confirmed work summary is available yet.',
    ar: 'لا يتوفر ملخص عمل مؤكد حتى الآن.',
    ur: 'ابھی تک کوئی تصدیق شدہ کام کا خلاصہ دستیاب نہیں ہے۔',
    hi: 'अभी तक कोई पुष्टि किया गया कार्य सारांश उपलब्ध नहीं है।',
  );
  static const noTodayFactsDescription = TranslatableString(
    en: 'Your available workspaces remain below; Yorks will add only facts it can prove for this account.',
    ar: 'تظل مساحات عملك المتاحة أدناه؛ سيضيف يوركس فقط الحقائق التي يمكنه إثباتها لهذا الحساب.',
    ur: 'آپ کی دستیاب ورک اسپیس نیچے موجود ہیں؛ یورکس صرف وہ حقائق شامل کرے گا جن کی اس اکاؤنٹ کے لیے تصدیق کر سکے۔',
    hi: 'आपके उपलब्ध कार्यस्थल नीचे बने रहते हैं; यॉर्क्स केवल वे तथ्य जोड़ेगा जिन्हें वह इस खाते के लिए साबित कर सकता है।',
  );
  static const noQuickActions = TranslatableString(
    en: 'No additional workspace is confirmed right now.',
    ar: 'لا توجد مساحة عمل إضافية مؤكدة حالياً.',
    ur: 'اس وقت کوئی اضافی ورک اسپیس تصدیق شدہ نہیں ہے۔',
    hi: 'अभी कोई अतिरिक्त कार्यस्थल पुष्टि नहीं हुआ है।',
  );
  static const noQuickActionsDescription = TranslatableString(
    en: 'If you need a workspace, ask an authorized Yorks administrator to review your access.',
    ar: 'إذا احتجت إلى مساحة عمل، اطلب من مسؤول يوركس مخول مراجعة صلاحيتك.',
    ur: 'اگر آپ کو کسی ورک اسپیس کی ضرورت ہے تو مجاز یورکس ایڈمنسٹریٹر سے اپنی رسائی کا جائزہ لینے کو کہیں۔',
    hi: 'यदि आपको किसी कार्यस्थल की आवश्यकता है, तो किसी अधिकृत यॉर्क्स व्यवस्थापक से अपनी पहुंच की समीक्षा करने को कहें।',
  );
  static const technicalProjectScope = TranslatableString(
    en: 'Technical projects',
    ar: 'المشاريع الفنية',
    ur: 'تکنیکی پروجیکٹس',
    hi: 'तकनीकी परियोजनाएं',
  );
  static const accountsProjectScope = TranslatableString(
    en: 'Accounts projects',
    ar: 'مشاريع الحسابات',
    ur: 'اکاؤنٹس پروجیکٹس',
    hi: 'खाता परियोजनाएं',
  );
  static const directMembershipScope = TranslatableString(
    en: 'Direct project assignments',
    ar: 'تعيينات المشروع المباشرة',
    ur: 'براہ راست پروجیکٹ اسائنمنٹس',
    hi: 'प्रत्यक्ष परियोजना असाइनमेंट',
  );
  static const accessSource = TranslatableString(
    en: 'Access source',
    ar: 'مصدر الوصول',
    ur: 'رسائی کا ذریعہ',
    hi: 'पहुंच का स्रोत',
  );
  static const serverConfirmed = TranslatableString(
    en: 'Server confirmed',
    ar: 'تم التأكيد من الخادم',
    ur: 'سرور سے تصدیق شدہ',
    hi: 'सर्वर से पुष्टि की गई',
  );
  static const accountScopeRefresh = TranslatableString(
    en: 'Refresh access',
    ar: 'تحديث الوصول',
    ur: 'رسائی تازہ کریں',
    hi: 'पहुंच रीफ़्रेश करें',
  );
  static const accountScopeRefreshDescription = TranslatableString(
    en: 'Check the latest Yorks role, scope and available workspace actions.',
    ar: 'تحقق من أحدث دور ونطاق وإجراءات مساحة العمل المتاحة في يوركس.',
    ur: 'یورکس کے تازہ ترین کردار، دائرے اور دستیاب ورک اسپیس اقدامات کی جانچ کریں۔',
    hi: 'नवीनतम यॉर्क्स भूमिका, दायरा और उपलब्ध कार्यस्थल कार्यों की जांच करें।',
  );
  static const workerLinked = TranslatableString(
    en: 'Linked Workforce record',
    ar: 'سجل قوى عاملة مرتبط',
    ur: 'منسلک ورک فورس ریکارڈ',
    hi: 'लिंक किया गया कार्यबल रिकॉर्ड',
  );
  static const workerLinkedDescription = TranslatableString(
    en: 'This record identifies your work profile. It does not grant attendance, time-entry or assignment authority.',
    ar: 'يحدد هذا السجل ملف عملك. لا يمنح صلاحية الحضور أو إدخال الوقت أو التعيين.',
    ur: 'یہ ریکارڈ آپ کے ورک پروفائل کی شناخت کرتا ہے۔ یہ حاضری، وقت درج کرنے یا اسائنمنٹ کی اجازت نہیں دیتا۔',
    hi: 'यह रिकॉर्ड आपके कार्य प्रोफ़ाइल की पहचान करता है। यह उपस्थिति, समय प्रविष्टि या असाइनमेंट अधिकार नहीं देता।',
  );
  static const workerNotLinked = TranslatableString(
    en: 'No Workforce record is linked',
    ar: 'لا يوجد سجل قوى عاملة مرتبط',
    ur: 'کوئی ورک فورس ریکارڈ منسلک نہیں ہے',
    hi: 'कोई कार्यबल रिकॉर्ड लिंक नहीं है',
  );
  static const workerNotLinkedDescription = TranslatableString(
    en: 'Your Yorks account still works normally. An authorized Workforce manager can link a separate work record when needed.',
    ar: 'يستمر حساب يوركس في العمل بشكل طبيعي. يمكن لمدير القوى العاملة المخول ربط سجل عمل منفصل عند الحاجة.',
    ur: 'آپ کا یورکس اکاؤنٹ معمول کے مطابق کام کرتا رہے گا۔ ضرورت پڑنے پر مجاز ورک فورس مینیجر ایک الگ ورک ریکارڈ منسلک کر سکتا ہے۔',
    hi: 'आपका यॉर्क्स खाता सामान्य रूप से काम करता रहता है। जरूरत होने पर अधिकृत कार्यबल प्रबंधक अलग कार्य रिकॉर्ड लिंक कर सकता है।',
  );
  static const workerNumber = TranslatableString(
    en: 'Worker number',
    ar: 'رقم العامل',
    ur: 'ورکر نمبر',
    hi: 'कर्मी संख्या',
  );
  static const workRecordName = TranslatableString(
    en: 'Work record name',
    ar: 'اسم سجل العمل',
    ur: 'ورک ریکارڈ کا نام',
    hi: 'कार्य रिकॉर्ड नाम',
  );
  static const lastVerified = TranslatableString(
    en: 'Last verified',
    ar: 'آخر تحقق',
    ur: 'آخری تصدیق',
    hi: 'अंतिम पुष्टि',
  );
  static const designation = TranslatableString(
    en: 'Designation',
    ar: 'المسمى الوظيفي',
    ur: 'عہدہ',
    hi: 'पदनाम',
  );
  static const department = TranslatableString(
    en: 'Department',
    ar: 'القسم',
    ur: 'شعبہ',
    hi: 'विभाग',
  );
  static const workCategory = TranslatableString(
    en: 'Work category',
    ar: 'فئة العمل',
    ur: 'کام کی قسم',
    hi: 'कार्य श्रेणी',
  );
  static const workStatus = TranslatableString(
    en: 'Work status',
    ar: 'حالة العمل',
    ur: 'کام کی حالت',
    hi: 'कार्य स्थिति',
  );
  static const accountsWorkspace = TranslatableString(
    en: 'Accounts',
    ar: 'الحسابات',
    ur: 'اکاؤنٹس',
    hi: 'लेखांकन',
  );
  static const inventoryWorkspace = TranslatableString(
    en: 'Inventory',
    ar: 'المخزون',
    ur: 'انوینٹری',
    hi: 'इन्वेंट्री',
  );
  static const returnsWorkspace = TranslatableString(
    en: 'Material returns',
    ar: 'مرتجعات المواد',
    ur: 'میٹریل ریٹرنز',
    hi: 'सामग्री वापसी',
  );
  static const teamChatWorkspace = TranslatableString(
    en: 'Team chat',
    ar: 'دردشة الفريق',
    ur: 'ٹیم چیٹ',
    hi: 'टीम चैट',
  );
  static const configurationWorkspace = TranslatableString(
    en: 'Configuration',
    ar: 'الإعدادات',
    ur: 'کنفیگریشن',
    hi: 'कॉन्फ़िगरेशन',
  );
  static const analyticsWorkspace = TranslatableString(
    en: 'Analytics',
    ar: 'التحليلات',
    ur: 'اینالیٹکس',
    hi: 'विश्लेषण',
  );

  static String todayMetricTitle(String key, AppLanguage language) =>
      switch (key) {
        'technical_projects' => switch (language) {
          AppLanguage.english => 'Projects you can open',
          AppLanguage.arabic => 'المشاريع التي يمكنك فتحها',
          AppLanguage.urdu => 'پروجیکٹس جو آپ کھول سکتے ہیں',
          AppLanguage.hindi => 'वे परियोजनाएं जिन्हें आप खोल सकते हैं',
        },
        'material_requests_needing_action' => switch (language) {
          AppLanguage.english => 'Requests needing you',
          AppLanguage.arabic => 'طلبات تحتاج إلى إجراء منك',
          AppLanguage.urdu => 'آپ کی کارروائی کی منتظر درخواستیں',
          AppLanguage.hindi => 'वे अनुरोध जिन्हें आपकी कार्रवाई चाहिए',
        },
        'material_requests_open' => switch (language) {
          AppLanguage.english => 'Open material requests',
          AppLanguage.arabic => 'طلبات المواد المفتوحة',
          AppLanguage.urdu => 'کھلی میٹریل درخواستیں',
          AppLanguage.hindi => 'खुले सामग्री अनुरोध',
        },
        'accounts_projects' => switch (language) {
          AppLanguage.english => 'Accounts projects',
          AppLanguage.arabic => 'مشاريع الحسابات',
          AppLanguage.urdu => 'اکاؤنٹس پروجیکٹس',
          AppLanguage.hindi => 'खाता परियोजनाएं',
        },
        _ => serverConfirmed.active(language),
      };

  static String todayMetricDescription(String key, AppLanguage language) =>
      switch (key) {
        'technical_projects' => switch (language) {
          AppLanguage.english => 'Current technical project scope',
          AppLanguage.arabic => 'نطاق المشروع الفني الحالي',
          AppLanguage.urdu => 'موجودہ تکنیکی پروجیکٹ دائرہ',
          AppLanguage.hindi => 'वर्तमान तकनीकी परियोजना दायरा',
        },
        'material_requests_needing_action' => switch (language) {
          AppLanguage.english => 'Current follow-up confirmed by Yorks',
          AppLanguage.arabic => 'متابعة حالية مؤكدة من يوركس',
          AppLanguage.urdu => 'یورکس کی تصدیق شدہ موجودہ فالو اَپ',
          AppLanguage.hindi => 'यॉर्क्स द्वारा पुष्टि किया गया वर्तमान फॉलो-अप',
        },
        'material_requests_open' => switch (language) {
          AppLanguage.english => 'Readable requests that are not closed',
          AppLanguage.arabic => 'طلبات قابلة للقراءة لم يتم إغلاقها',
          AppLanguage.urdu => 'قابلِ مطالعہ درخواستیں جو بند نہیں ہوئیں',
          AppLanguage.hindi => 'पढ़े जा सकने वाले अनुरोध जो बंद नहीं हैं',
        },
        'accounts_projects' => switch (language) {
          AppLanguage.english => 'Confirmed Accounts portfolio scope',
          AppLanguage.arabic => 'نطاق محفظة الحسابات المؤكد',
          AppLanguage.urdu => 'تصدیق شدہ اکاؤنٹس پورٹ فولیو دائرہ',
          AppLanguage.hindi => 'पुष्टि किया गया खाता पोर्टफोलियो दायरा',
        },
        _ => serverConfirmed.active(language),
      };

  static String actionTitle(String actionId, AppLanguage language) =>
      switch (actionId) {
        'open_projects' => AppStrings.projects.active(language),
        'open_material_requests' => AppStrings.materialRequests.active(
          language,
        ),
        'open_accounts' => accountsWorkspace.active(language),
        'open_inventory' => inventoryWorkspace.active(language),
        'open_returns' => returnsWorkspace.active(language),
        'open_chat' => teamChatWorkspace.active(language),
        'open_rentals' => AppStrings.rentals.active(language),
        'open_users' => AppStrings.userManagement.active(language),
        'open_configuration' => configurationWorkspace.active(language),
        'open_audit' => AppStrings.auditTrail.active(language),
        'open_analytics' => analyticsWorkspace.active(language),
        _ => serverConfirmed.active(language),
      };

  static String actionDescription(
    String actionId,
    AppLanguage language,
  ) => switch (actionId) {
    'open_projects' => switch (language) {
      AppLanguage.english => 'Open your authorized project workspace.',
      AppLanguage.arabic => 'افتح مساحة المشروع المصرح بها.',
      AppLanguage.urdu => 'اپنی مجاز پروجیکٹ ورک اسپیس کھولیں۔',
      AppLanguage.hindi => 'अपना अधिकृत परियोजना कार्यस्थल खोलें।',
    },
    'open_material_requests' => switch (language) {
      AppLanguage.english =>
        'Review readable material requests and their next action.',
      AppLanguage.arabic =>
        'راجع طلبات المواد القابلة للقراءة وإجراءها التالي.',
      AppLanguage.urdu =>
        'قابلِ مطالعہ میٹریل درخواستوں اور ان کے اگلے اقدام کا جائزہ لیں۔',
      AppLanguage.hindi =>
        'पढ़े जा सकने वाले सामग्री अनुरोधों और उनकी अगली कार्रवाई की समीक्षा करें।',
    },
    'open_accounts' => switch (language) {
      AppLanguage.english => 'Open the confirmed Accounts portfolio.',
      AppLanguage.arabic => 'افتح محفظة الحسابات المؤكدة.',
      AppLanguage.urdu => 'تصدیق شدہ اکاؤنٹس پورٹ فولیو کھولیں۔',
      AppLanguage.hindi => 'पुष्टि किया गया खाता पोर्टफोलियो खोलें।',
    },
    'open_inventory' => switch (language) {
      AppLanguage.english => 'Open the authorized inventory workspace.',
      AppLanguage.arabic => 'افتح مساحة المخزون المصرح بها.',
      AppLanguage.urdu => 'مجاز انوینٹری ورک اسپیس کھولیں۔',
      AppLanguage.hindi => 'अधिकृत इन्वेंट्री कार्यस्थल खोलें।',
    },
    'open_returns' => switch (language) {
      AppLanguage.english => 'Review authorized material returns.',
      AppLanguage.arabic => 'راجع مرتجعات المواد المصرح بها.',
      AppLanguage.urdu => 'مجاز میٹریل ریٹرنز کا جائزہ لیں۔',
      AppLanguage.hindi => 'अधिकृत सामग्री रिटर्न की समीक्षा करें।',
    },
    'open_chat' => switch (language) {
      AppLanguage.english => 'Open your Yorks team conversations.',
      AppLanguage.arabic => 'افتح محادثات فريق يوركس الخاصة بك.',
      AppLanguage.urdu => 'اپنی یورکس ٹیم گفتگوئیں کھولیں۔',
      AppLanguage.hindi => 'अपने यॉर्क्स टीम वार्तालाप खोलें।',
    },
    'open_rentals' => switch (language) {
      AppLanguage.english => 'Open authorized rental operations.',
      AppLanguage.arabic => 'افتح عمليات الإيجار المصرح بها.',
      AppLanguage.urdu => 'مجاز رینٹل آپریشنز کھولیں۔',
      AppLanguage.hindi => 'अधिकृत किराया संचालन खोलें।',
    },
    'open_users' => switch (language) {
      AppLanguage.english => 'Review the authorized Yorks directory.',
      AppLanguage.arabic => 'راجع دليل يوركس المصرح به.',
      AppLanguage.urdu => 'مجاز یورکس ڈائریکٹری کا جائزہ لیں۔',
      AppLanguage.hindi => 'अधिकृत यॉर्क्स निर्देशिका की समीक्षा करें।',
    },
    'open_configuration' => switch (language) {
      AppLanguage.english => 'Open the authorized configuration workspace.',
      AppLanguage.arabic => 'افتح مساحة الإعدادات المصرح بها.',
      AppLanguage.urdu => 'مجاز کنفیگریشن ورک اسپیس کھولیں۔',
      AppLanguage.hindi => 'अधिकृत कॉन्फ़िगरेशन कार्यस्थल खोलें।',
    },
    'open_audit' => switch (language) {
      AppLanguage.english => 'Review the protected audit trail.',
      AppLanguage.arabic => 'راجع سجل التدقيق المحمي.',
      AppLanguage.urdu => 'محفوظ آڈٹ ٹریل کا جائزہ لیں۔',
      AppLanguage.hindi => 'सुरक्षित ऑडिट ट्रेल की समीक्षा करें।',
    },
    'open_analytics' => switch (language) {
      AppLanguage.english => 'Open the authorized Yorks Analytics view.',
      AppLanguage.arabic => 'افتح عرض تحليلات يوركس المصرح به.',
      AppLanguage.urdu => 'مجاز یورکس اینالیٹکس منظر کھولیں۔',
      AppLanguage.hindi => 'अधिकृत यॉर्क्स एनालिटिक्स दृश्य खोलें।',
    },
    _ => serverConfirmed.active(language),
  };

  static String sourceKind(String source, AppLanguage language) =>
      switch (source) {
        'role_default' => switch (language) {
          AppLanguage.english => 'Role template',
          AppLanguage.arabic => 'قالب الدور',
          AppLanguage.urdu => 'کردار ٹیمپلیٹ',
          AppLanguage.hindi => 'भूमिका टेम्पलेट',
        },
        'custom_grant' || 'explicit_grant' => switch (language) {
          AppLanguage.english => 'Direct grant',
          AppLanguage.arabic => 'منح مباشر',
          AppLanguage.urdu => 'براہ راست اجازت',
          AppLanguage.hindi => 'प्रत्यक्ष अनुदान',
        },
        'legacy_preserved' || 'legacy_override' => switch (language) {
          AppLanguage.english => 'Preserved access',
          AppLanguage.arabic => 'وصول محفوظ',
          AppLanguage.urdu => 'محفوظ رسائی',
          AppLanguage.hindi => 'संरक्षित पहुंच',
        },
        _ => serverConfirmed.active(language),
      };

  static String workerType(String type, AppLanguage language) => switch (type) {
    'yorks_employee' => switch (language) {
      AppLanguage.english => 'Yorks employee',
      AppLanguage.arabic => 'موظف يوركس',
      AppLanguage.urdu => 'یورکس ملازم',
      AppLanguage.hindi => 'यॉर्क्स कर्मचारी',
    },
    'temporary_worker' => switch (language) {
      AppLanguage.english => 'Temporary worker',
      AppLanguage.arabic => 'عامل مؤقت',
      AppLanguage.urdu => 'عارضی ورکر',
      AppLanguage.hindi => 'अस्थायी कर्मी',
    },
    'subcontractor_worker' => switch (language) {
      AppLanguage.english => 'Subcontractor worker',
      AppLanguage.arabic => 'عامل مقاول باطن',
      AppLanguage.urdu => 'ذیلی ٹھیکیدار ورکر',
      AppLanguage.hindi => 'उपठेकेदार कर्मी',
    },
    'agency_worker' => switch (language) {
      AppLanguage.english => 'Agency worker',
      AppLanguage.arabic => 'عامل وكالة',
      AppLanguage.urdu => 'ایجنسی ورکر',
      AppLanguage.hindi => 'एजेंसी कर्मी',
    },
    _ => serverConfirmed.active(language),
  };

  static String workerStatus(String status, AppLanguage language) =>
      switch (status) {
        'active' => active.active(language),
        'inactive' => switch (language) {
          AppLanguage.english => 'Inactive',
          AppLanguage.arabic => 'غير نشط',
          AppLanguage.urdu => 'غیر فعال',
          AppLanguage.hindi => 'निष्क्रिय',
        },
        'left_company' => switch (language) {
          AppLanguage.english => 'Left company',
          AppLanguage.arabic => 'غادر الشركة',
          AppLanguage.urdu => 'کمپنی چھوڑ دی',
          AppLanguage.hindi => 'कंपनी छोड़ दी',
        },
        'suspended' => switch (language) {
          AppLanguage.english => 'Suspended',
          AppLanguage.arabic => 'موقوف',
          AppLanguage.urdu => 'معطل',
          AppLanguage.hindi => 'निलंबित',
        },
        _ => serverConfirmed.active(language),
      };

  static String role(YorksV1Role role, AppLanguage language) => switch (role) {
    YorksV1Role.projectEngineer => AppStrings.projectEngineerRole.active(
      language,
    ),
    YorksV1Role.siteEngineer => AppStrings.siteEngineerRole.active(language),
    YorksV1Role.seniorMechanicalEngineer =>
      AppStrings.seniorMechanicalEngineerRole.active(language),
    YorksV1Role.projectManager => AppStrings.projectManagerRole.active(
      language,
    ),
    YorksV1Role.workshopInCharge => AppStrings.workshopInChargeRole.active(
      language,
    ),
    YorksV1Role.documentController => AppStrings.documentControllerRole.active(
      language,
    ),
    YorksV1Role.accountant => AppStrings.accountantRole.active(language),
    YorksV1Role.pr => AppStrings.prRole.active(language),
    YorksV1Role.procurement => AppStrings.procurementRole.active(language),
    YorksV1Role.admin => AppStrings.adminRole.active(language),
  };

  static String queuedChanges(
    AppLanguage language,
    int count,
  ) => switch (language) {
    AppLanguage.english =>
      '$count local change${count == 1 ? '' : 's'} will retry when the connection returns.',
    AppLanguage.arabic =>
      'ستتم إعادة محاولة $count من التغييرات المحلية عند عودة الاتصال.',
    AppLanguage.urdu =>
      'کنکشن واپس آنے پر $count مقامی تبدیلیوں کی دوبارہ کوشش ہوگی۔',
    AppLanguage.hindi =>
      'कनेक्शन लौटने पर $count स्थानीय बदलाव फिर भेजे जाएंगे।',
  };

  static String syncingCount(
    AppLanguage language,
    int count,
  ) => switch (language) {
    AppLanguage.english =>
      '$count queued change${count == 1 ? ' is' : 's are'} waiting for server confirmation.',
    AppLanguage.arabic => '$count من التغييرات تنتظر تأكيد الخادم.',
    AppLanguage.urdu => '$count قطار شدہ تبدیلیاں سرور کی تصدیق کی منتظر ہیں۔',
    AppLanguage.hindi =>
      '$count कतारबद्ध बदलाव सर्वर पुष्टि की प्रतीक्षा में हैं।',
  };

  static String failedCount(
    AppLanguage language,
    int count,
  ) => switch (language) {
    AppLanguage.english =>
      '$count saved local change${count == 1 ? '' : 's'} could not be submitted. Retry preserves the original command identity.',
    AppLanguage.arabic =>
      'تعذر إرسال $count من التغييرات المحلية المحفوظة. تحافظ إعادة المحاولة على هوية الأمر الأصلية.',
    AppLanguage.urdu =>
      '$count محفوظ مقامی تبدیلیاں جمع نہیں ہو سکیں۔ دوبارہ کوشش اصل کمانڈ شناخت برقرار رکھتی ہے۔',
    AppLanguage.hindi =>
      '$count सहेजे गए स्थानीय बदलाव भेजे नहीं जा सके। पुनः प्रयास मूल कमांड पहचान सुरक्षित रखता है।',
  };
}
