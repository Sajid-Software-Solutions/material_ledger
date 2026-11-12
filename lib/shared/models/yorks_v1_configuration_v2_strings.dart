/// Configuration copy (English, Arabic, Urdu, Hindi).
library;

import 'app_language.dart';
import 'app_strings.dart';
import 'yorks_v1_attendance_strings.dart';

typedef _T = TranslatableString;

abstract final class ConfigStrings {
  static String t(
    TranslatableString value,
    AppLanguage language, [
    Map<String, Object?>? v,
  ]) => AttendanceStrings.t(value, language, v);

  // ─── Page ──────────────────────────────────────────────────────────────────
  static const title = _T(
    en: 'Configuration',
    ar: 'الإعدادات',
    ur: 'ترتیبات',
    hi: 'कॉन्फ़िगरेशन',
  );
  static const intro = _T(
    en: 'Set up the company and how each part of the app works. Changes apply to new records; issued documents keep their copy.',
    ar: 'اضبط بيانات الشركة وطريقة عمل كل جزء من التطبيق. تسري التغييرات على السجلات الجديدة؛ وتحتفظ المستندات الصادرة بنسختها.',
    ur: 'کمپنی اور ایپ کے ہر حصے کی ترتیب کریں۔ تبدیلیاں نئے ریکارڈز پر لاگو ہوتی ہیں؛ جاری شدہ دستاویزات اپنی نقل رکھتی ہیں۔',
    hi: 'कंपनी और ऐप के हर हिस्से को सेट करें। बदलाव नए रिकॉर्ड पर लागू होते हैं; जारी दस्तावेज़ अपनी प्रति रखते हैं।',
  );
  static const sections = _T(
    en: 'Sections',
    ar: 'الأقسام',
    ur: 'حصے',
    hi: 'अनुभाग',
  );
  static const readOnly = _T(
    en: 'View only',
    ar: 'للعرض فقط',
    ur: 'صرف دیکھنے کے لیے',
    hi: 'केवल देखें',
  );

  // ─── Navigation groups ─────────────────────────────────────────────────────
  static const navStart = _T(
    en: 'Start here',
    ar: 'ابدأ هنا',
    ur: 'یہاں سے شروع کریں',
    hi: 'यहाँ से शुरू करें',
  );
  static const navCompany = _T(
    en: 'Company',
    ar: 'الشركة',
    ur: 'کمپنی',
    hi: 'कंपनी',
  );
  static const navOperations = _T(
    en: 'Operations',
    ar: 'العمليات',
    ur: 'آپریشنز',
    hi: 'संचालन',
  );
  static const navFinance = _T(
    en: 'Finance',
    ar: 'المالية',
    ur: 'مالیات',
    hi: 'वित्त',
  );
  static const navSystem = _T(
    en: 'System',
    ar: 'النظام',
    ur: 'سسٹم',
    hi: 'सिस्टम',
  );

  // ─── Roles at a glance ─────────────────────────────────────────────────────
  static const rolesTitle = _T(
    en: 'Roles at a glance',
    ar: 'الأدوار باختصار',
    ur: 'کردار ایک نظر میں',
    hi: 'भूमिकाएँ एक नज़र में',
  );
  static const rolesSub = _T(
    en: 'What each role can do. Change a person\'s role or add individual permissions in User Management.',
    ar: 'ما يستطيع كل دور فعله. غيّر دور الشخص أو أضف صلاحيات فردية من إدارة المستخدمين.',
    ur: 'ہر کردار کیا کر سکتا ہے۔ کسی کا کردار بدلنے یا انفرادی اجازتیں دینے کے لیے یوزر مینجمنٹ استعمال کریں۔',
    hi: 'हर भूमिका क्या कर सकती है। किसी की भूमिका बदलने या व्यक्तिगत अनुमतियाँ देने के लिए उपयोगकर्ता प्रबंधन का उपयोग करें।',
  );
  static const roleAdmin = _T(
    en: 'Everything, including Configuration and audited corrections.',
    ar: 'كل شيء، بما في ذلك الإعدادات والتصحيحات المدققة.',
    ur: 'سب کچھ، بشمول ترتیبات اور آڈٹ شدہ تصحیحات۔',
    hi: 'सब कुछ, कॉन्फ़िगरेशन और ऑडिट किए गए सुधार सहित।',
  );
  static const roleSme = _T(
    en: 'Every project; approves for any project; manages users; views stock.',
    ar: 'كل المشاريع؛ يعتمد لأي مشروع؛ يدير المستخدمين؛ يطّلع على المخزون.',
    ur: 'ہر پروجیکٹ؛ کسی بھی پروجیکٹ کے لیے منظوری؛ صارفین کا انتظام؛ اسٹاک دیکھنا۔',
    hi: 'हर प्रोजेक्ट; किसी भी प्रोजेक्ट के लिए स्वीकृति; उपयोगकर्ता प्रबंधन; स्टॉक देखना।',
  );
  static const roleGlobalEngineer = _T(
    en: 'Project Manager, Workshop In-Charge, Document Controller: every project, approves like a Project Engineer.',
    ar: 'مدير المشروع ومسؤول الورشة ومراقب المستندات: كل المشاريع، ويعتمدون كمهندس المشروع.',
    ur: 'پروجیکٹ مینیجر، ورکشاپ انچارج، دستاویز کنٹرولر: ہر پروجیکٹ، پروجیکٹ انجینئر کی طرح منظوری۔',
    hi: 'प्रोजेक्ट मैनेजर, वर्कशॉप इंचार्ज, दस्तावेज़ नियंत्रक: हर प्रोजेक्ट, प्रोजेक्ट इंजीनियर की तरह स्वीकृति।',
  );
  static const rolePe = _T(
    en: 'Their projects: BOQ, team, requests, approvals, receipts, returns, attendance confirmation.',
    ar: 'مشاريعه: جداول الكميات والفريق والطلبات والاعتمادات والاستلام والإرجاع وتأكيد الحضور.',
    ur: 'اپنے پروجیکٹس: BOQ، ٹیم، درخواستیں، منظوریاں، وصولی، واپسی، حاضری کی تصدیق۔',
    hi: 'अपने प्रोजेक्ट: BOQ, टीम, अनुरोध, स्वीकृतियाँ, प्राप्ति, वापसी, उपस्थिति पुष्टि।',
  );
  static const roleSe = _T(
    en: 'Their projects: BOQ, requests, receipts, returns, attendance and crew requests.',
    ar: 'مشاريعه: جداول الكميات والطلبات والاستلام والإرجاع والحضور وطلبات الطواقم.',
    ur: 'اپنے پروجیکٹس: BOQ، درخواستیں، وصولی، واپسی، حاضری اور عملے کی درخواستیں۔',
    hi: 'अपने प्रोजेक्ट: BOQ, अनुरोध, प्राप्ति, वापसी, उपस्थिति और क्रू अनुरोध।',
  );
  static const roleProcurement = _T(
    en: 'Arranges requests, keeps stock, dispatches and confirms returns. Never approves its own arrangement.',
    ar: 'يرتّب الطلبات ويحفظ المخزون ويرسل ويؤكد الإرجاع. لا يعتمد ترتيبه بنفسه أبدًا.',
    ur: 'درخواستوں کی ترتیب، اسٹاک، ڈسپیچ اور واپسی کی تصدیق۔ اپنی ترتیب کبھی خود منظور نہیں کرتا۔',
    hi: 'अनुरोधों की व्यवस्था, स्टॉक, प्रेषण और वापसी की पुष्टि। अपनी व्यवस्था कभी खुद स्वीकृत नहीं करता।',
  );
  static const roleAccountant = _T(
    en: 'Project Accounts: claims, certification, receipts, cheques and supplier bills. Reads Workforce.',
    ar: 'حسابات المشاريع: المطالبات والاعتماد والمقبوضات والشيكات وفواتير الموردين. يطّلع على القوى العاملة.',
    ur: 'پروجیکٹ اکاؤنٹس: کلیمز، تصدیق، وصولیاں، چیک اور سپلائر بلز۔ افرادی قوت دیکھ سکتا ہے۔',
    hi: 'प्रोजेक्ट लेखा: दावे, प्रमाणन, प्राप्तियाँ, चेक और आपूर्तिकर्ता बिल। कार्यबल देख सकता है।',
  );
  static const rolePr = _T(
    en: 'People and HR: users, worker records, Workforce, leave, crew request assignment and Rentals. Reads projects and Accounts.',
    ar: 'الأفراد والموارد البشرية: المستخدمون وسجلات العمال والقوى العاملة والإجازات وتعيين طلبات الطواقم والإيجارات. يطّلع على المشاريع والحسابات.',
    ur: 'افراد اور ایچ آر: صارفین، ورکر ریکارڈز، افرادی قوت، رخصت، عملے کی درخواستوں کی تقرری اور کرایے۔ پروجیکٹس اور اکاؤنٹس دیکھ سکتا ہے۔',
    hi: 'लोग और एचआर: उपयोगकर्ता, वर्कर रिकॉर्ड, कार्यबल, अवकाश, क्रू अनुरोध सौंपना और किराया। प्रोजेक्ट और लेखा देख सकता है।',
  );

  // ─── Section names and lines ───────────────────────────────────────────────
  static const secChecklist = _T(
    en: 'Setup checklist',
    ar: 'قائمة الإعداد',
    ur: 'سیٹ اپ فہرست',
    hi: 'सेटअप सूची',
  );
  static const secChecklistSub = _T(
    en: 'What still needs attention',
    ar: 'ما يزال يحتاج إلى انتباه',
    ur: 'جن چیزوں پر ابھی توجہ درکار ہے',
    hi: 'जिन पर अभी ध्यान देना है',
  );
  static const secCompany = _T(
    en: 'Company & documents',
    ar: 'الشركة والمستندات',
    ur: 'کمپنی اور دستاویزات',
    hi: 'कंपनी और दस्तावेज़',
  );
  static const secCompanySub = _T(
    en: 'Names, contact, bank and letterhead',
    ar: 'الأسماء والتواصل والبنك وترويسة المستندات',
    ur: 'نام، رابطہ، بینک اور لیٹر ہیڈ',
    hi: 'नाम, संपर्क, बैंक और लेटरहेड',
  );
  static const secProjects = _T(
    en: 'Projects & BOQ',
    ar: 'المشاريع وجداول الكميات',
    ur: 'پروجیکٹس اور BOQ',
    hi: 'प्रोजेक्ट और BOQ',
  );
  static const secProjectsSub = _T(
    en: 'Default folders for new buildings',
    ar: 'المجلدات الافتراضية للمباني الجديدة',
    ur: 'نئی عمارتوں کے لیے ڈیفالٹ فولڈر',
    hi: 'नई इमारतों के डिफ़ॉल्ट फ़ोल्डर',
  );
  static const secRequests = _T(
    en: 'Material requests',
    ar: 'طلبات المواد',
    ur: 'مواد کی درخواستیں',
    hi: 'सामग्री अनुरोध',
  );
  static const secRequestsSub = _T(
    en: 'Request rules, company categories and departments',
    ar: 'قواعد الطلبات وفئات الشركة والأقسام',
    ur: 'درخواست کے اصول، کمپنی زمرے اور شعبے',
    hi: 'अनुरोध नियम, कंपनी श्रेणियाँ और विभाग',
  );
  static const secInventory = _T(
    en: 'Inventory & procurement',
    ar: 'المخزون والمشتريات',
    ur: 'انوینٹری اور خریداری',
    hi: 'इन्वेंट्री और खरीद',
  );
  static const secInventorySub = _T(
    en: 'Categories, units and sourcing rule',
    ar: 'الفئات والوحدات وقاعدة التوريد',
    ur: 'زمرے، اکائیاں اور سورسنگ اصول',
    hi: 'श्रेणियाँ, इकाइयाँ और सोर्सिंग नियम',
  );
  static const secAccounts = _T(
    en: 'Accounts',
    ar: 'الحسابات',
    ur: 'اکاؤنٹس',
    hi: 'लेखा',
  );
  static const secAccountsSub = _T(
    en: 'Payment terms and billing stages for new projects',
    ar: 'شروط الدفع ومراحل الفوترة للمشاريع الجديدة',
    ur: 'نئے پروجیکٹس کے لیے ادائیگی کی شرائط اور بلنگ مراحل',
    hi: 'नए प्रोजेक्ट के लिए भुगतान शर्तें और बिलिंग चरण',
  );
  static const secWorkforce = _T(
    en: 'Workforce',
    ar: 'القوى العاملة',
    ur: 'افرادی قوت',
    hi: 'कार्यबल',
  );
  static const secWorkforceSub = _T(
    en: 'Holidays, shifts, locations and trades',
    ar: 'العطلات والورديات والمواقع والمهن',
    ur: 'چھٹیاں، شفٹیں، مقامات اور ہنر',
    hi: 'छुट्टियाँ, शिफ़्ट, स्थान और ट्रेड',
  );
  static const secRentals = _T(
    en: 'Rentals',
    ar: 'الإيجارات',
    ur: 'کرایے',
    hi: 'किराया',
  );
  static const secRentalsSub = _T(
    en: 'Lease, cheque and rent reminders',
    ar: 'تذكيرات العقود والشيكات والإيجار',
    ur: 'لیز، چیک اور کرایے کی یاد دہانیاں',
    hi: 'लीज़, चेक और किराया अनुस्मारक',
  );
  static const secNotifications = _T(
    en: 'Notifications',
    ar: 'الإشعارات',
    ur: 'اطلاعات',
    hi: 'सूचनाएँ',
  );
  static const secNotificationsSub = _T(
    en: 'Phone and browser alerts, daily reminders',
    ar: 'تنبيهات الهاتف والمتصفح والتذكيرات اليومية',
    ur: 'فون اور براؤزر الرٹس، روزانہ یاد دہانیاں',
    hi: 'फ़ोन और ब्राउज़र अलर्ट, दैनिक अनुस्मारक',
  );
  static const secAccess = _T(
    en: 'Access & security',
    ar: 'الوصول والأمان',
    ur: 'رسائی اور سیکیورٹی',
    hi: 'पहुँच और सुरक्षा',
  );
  static const secAccessSub = _T(
    en: 'Users, roles and sign-in',
    ar: 'المستخدمون والأدوار وتسجيل الدخول',
    ur: 'صارفین، کردار اور سائن ان',
    hi: 'उपयोगकर्ता, भूमिकाएँ और साइन-इन',
  );
  static const secNumbering = _T(
    en: 'Document numbers',
    ar: 'أرقام المستندات',
    ur: 'دستاویز نمبر',
    hi: 'दस्तावेज़ संख्या',
  );
  static const secNumberingSub = _T(
    en: 'How each record is numbered',
    ar: 'كيف يُرقَّم كل سجل',
    ur: 'ہر ریکارڈ کا نمبر کیسے بنتا ہے',
    hi: 'हर रिकॉर्ड की संख्या कैसे बनती है',
  );
  static const secHistory = _T(
    en: 'History',
    ar: 'السجل',
    ur: 'تاریخچہ',
    hi: 'इतिहास',
  );
  static const secHistorySub = _T(
    en: 'Every saved change, who and why',
    ar: 'كل تغيير محفوظ ومن أجراه ولماذا',
    ur: 'ہر محفوظ تبدیلی، کس نے اور کیوں',
    hi: 'हर सहेजा बदलाव, किसने और क्यों',
  );

  // ─── Saving ────────────────────────────────────────────────────────────────
  static const changesPending = _T(
    en: '{n} unsaved changes',
    ar: '{n} تغييرات غير محفوظة',
    ur: '{n} غیر محفوظ تبدیلیاں',
    hi: '{n} बिना सहेजे बदलाव',
  );
  static const discard = _T(
    en: 'Discard',
    ar: 'تجاهل',
    ur: 'منسوخ کریں',
    hi: 'छोड़ें',
  );
  static const reviewSave = _T(
    en: 'Review and save',
    ar: 'مراجعة وحفظ',
    ur: 'جائزہ لیں اور محفوظ کریں',
    hi: 'समीक्षा करें और सहेजें',
  );
  static const reviewTitle = _T(
    en: 'Save {n} changes?',
    ar: 'حفظ {n} تغييرات؟',
    ur: '{n} تبدیلیاں محفوظ کریں؟',
    hi: '{n} बदलाव सहेजें?',
  );
  static const reviewBody = _T(
    en: 'They apply to new records from now on and are kept in History with your reason.',
    ar: 'تسري على السجلات الجديدة من الآن وتُحفظ في السجل مع سببك.',
    ur: 'یہ اب سے نئے ریکارڈز پر لاگو ہوں گی اور آپ کی وجہ کے ساتھ تاریخچے میں رہیں گی۔',
    hi: 'ये अब से नए रिकॉर्ड पर लागू होंगे और आपके कारण के साथ इतिहास में रहेंगे।',
  );
  static const reason = _T(
    en: 'Reason (at least 8 characters)',
    ar: 'السبب (8 أحرف على الأقل)',
    ur: 'وجہ (کم از کم 8 حروف)',
    hi: 'कारण (कम से कम 8 अक्षर)',
  );
  static const save = _T(en: 'Save', ar: 'حفظ', ur: 'محفوظ کریں', hi: 'सहेजें');
  static const saved = _T(
    en: 'Saved · version {v}',
    ar: 'تم الحفظ · الإصدار {v}',
    ur: 'محفوظ · ورژن {v}',
    hi: 'सहेजा गया · संस्करण {v}',
  );
  static const empty = _T(en: '—', ar: '—', ur: '—', hi: '—');
  static const on = _T(en: 'On', ar: 'تشغيل', ur: 'آن', hi: 'चालू');
  static const off = _T(en: 'Off', ar: 'إيقاف', ur: 'آف', hi: 'बंद');
  static const leaveTitle = _T(
    en: 'Discard unsaved changes?',
    ar: 'تجاهل التغييرات غير المحفوظة؟',
    ur: 'غیر محفوظ تبدیلیاں منسوخ کریں؟',
    hi: 'बिना सहेजे बदलाव छोड़ें?',
  );
  static const keepEditing = _T(
    en: 'Keep editing',
    ar: 'متابعة التحرير',
    ur: 'ترمیم جاری رکھیں',
    hi: 'संपादन जारी रखें',
  );

  // ─── Errors ────────────────────────────────────────────────────────────────
  static const errConflict = _T(
    en: 'Someone saved Configuration a moment ago. Reload to see their change, then make yours again.',
    ar: 'حفظ شخص الإعدادات قبل لحظات. أعد التحميل لترى تغييره ثم أعد تغييرك.',
    ur: 'کسی نے ابھی ترتیبات محفوظ کیں۔ ان کی تبدیلی دیکھنے کے لیے ری لوڈ کریں، پھر اپنی تبدیلی دوبارہ کریں۔',
    hi: 'किसी ने अभी कॉन्फ़िगरेशन सहेजा। उनका बदलाव देखने के लिए रीलोड करें, फिर अपना बदलाव दोबारा करें।',
  );
  static const errIban = _T(
    en: 'That IBAN is not valid. It starts with the country code, e.g. AE07 0331 2345 6789 0123 456.',
    ar: 'رقم الآيبان غير صالح. يبدأ برمز الدولة، مثل AE07 0331 2345 6789 0123 456.',
    ur: 'یہ IBAN درست نہیں۔ یہ ملک کے کوڈ سے شروع ہوتا ہے، جیسے AE07 0331 2345 6789 0123 456۔',
    hi: 'यह IBAN मान्य नहीं है। यह देश कोड से शुरू होता है, जैसे AE07 0331 2345 6789 0123 456।',
  );
  static const errTrn = _T(
    en: 'The TRN is the 15-digit tax registration number.',
    ar: 'الرقم الضريبي مكوّن من 15 رقمًا.',
    ur: 'TRN پندرہ ہندسوں کا ٹیکس رجسٹریشن نمبر ہے۔',
    hi: 'TRN 15 अंकों की कर पंजीकरण संख्या है।',
  );
  static const errEmail = _T(
    en: 'That email address is not valid.',
    ar: 'عنوان البريد الإلكتروني غير صالح.',
    ur: 'یہ ای میل پتہ درست نہیں۔',
    hi: 'यह ईमेल पता मान्य नहीं है।',
  );
  static const errRequired = _T(
    en: 'Legal and short names cannot be empty.',
    ar: 'لا يمكن ترك الاسم القانوني والمختصر فارغين.',
    ur: 'قانونی اور مختصر نام خالی نہیں ہو سکتے۔',
    hi: 'कानूनी और छोटा नाम खाली नहीं हो सकता।',
  );
  static const errWhatsapp = _T(
    en: 'Use the international format, e.g. +971501234567.',
    ar: 'استخدم الصيغة الدولية، مثل ‎+971501234567.',
    ur: 'بین الاقوامی فارمیٹ استعمال کریں، جیسے ‎+971501234567۔',
    hi: 'अंतरराष्ट्रीय प्रारूप का उपयोग करें, जैसे +971501234567।',
  );
  static const errStageTotal = _T(
    en: 'Active stages must add up to exactly 100%.',
    ar: 'يجب أن يكون مجموع المراحل النشطة 100% بالضبط.',
    ur: 'فعال مراحل کا مجموعہ بالکل 100% ہونا چاہیے۔',
    hi: 'सक्रिय चरणों का योग ठीक 100% होना चाहिए।',
  );
  static const errFolderRequired = _T(
    en: 'Keep at least one default folder on.',
    ar: 'أبقِ مجلدًا افتراضيًا واحدًا على الأقل مفعّلًا.',
    ur: 'کم از کم ایک ڈیفالٹ فولڈر آن رکھیں۔',
    hi: 'कम से कम एक डिफ़ॉल्ट फ़ोल्डर चालू रखें।',
  );
  static const errNameTaken = _T(
    en: 'That name is already used.',
    ar: 'هذا الاسم مستخدم بالفعل.',
    ur: 'یہ نام پہلے سے استعمال میں ہے۔',
    hi: 'यह नाम पहले से उपयोग में है।',
  );
  static const errPolicy = _T(
    en: 'Payment terms are 1–365 days and the reminder comes before them.',
    ar: 'شروط الدفع من 1 إلى 365 يومًا والتذكير يسبقها.',
    ur: 'ادائیگی کی شرائط 1 سے 365 دن ہیں اور یاد دہانی اس سے پہلے آتی ہے۔',
    hi: 'भुगतान शर्तें 1–365 दिन हैं और अनुस्मारक उससे पहले आता है।',
  );

  // ─── Checklist ─────────────────────────────────────────────────────────────
  static const chkBank = _T(
    en: 'Bank details on invoices',
    ar: 'بيانات البنك في الفواتير',
    ur: 'انوائسز پر بینک کی تفصیلات',
    hi: 'चालान पर बैंक विवरण',
  );
  static const chkBankMissing = _T(
    en: 'Missing — invoices print no bank block',
    ar: 'غير موجودة — الفواتير بلا بيانات بنك',
    ur: 'موجود نہیں — انوائسز پر بینک بلاک نہیں چھپتا',
    hi: 'नहीं हैं — चालान पर बैंक विवरण नहीं छपता',
  );
  static const chkTrn = _T(
    en: 'Tax registration number (TRN)',
    ar: 'الرقم الضريبي',
    ur: 'ٹیکس رجسٹریشن نمبر (TRN)',
    hi: 'कर पंजीकरण संख्या (TRN)',
  );
  static const chkPush = _T(
    en: 'Phone and browser alerts',
    ar: 'تنبيهات الهاتف والمتصفح',
    ur: 'فون اور براؤزر الرٹس',
    hi: 'फ़ोन और ब्राउज़र अलर्ट',
  );
  static const chkHolidays = _T(
    en: 'Public holidays for {year}',
    ar: 'العطلات الرسمية لعام {year}',
    ur: '{year} کی سرکاری چھٹیاں',
    hi: '{year} की सार्वजनिक छुट्टियाँ',
  );
  static const chkHolidaysNone = _T(
    en: 'None entered — holiday overtime will not be counted',
    ar: 'لم تُدخل أي عطلة — لن يُحتسب العمل الإضافي في العطلات',
    ur: 'کوئی درج نہیں — چھٹی کا اوور ٹائم شمار نہیں ہوگا',
    hi: 'कोई दर्ज नहीं — छुट्टी का ओवरटाइम नहीं गिना जाएगा',
  );
  static const chkHolidaysCount = _T(
    en: '{n} entered',
    ar: 'تم إدخال {n}',
    ur: '{n} درج',
    hi: '{n} दर्ज',
  );
  static const chkPr = _T(
    en: 'A PR user to assign crew requests',
    ar: 'مستخدم علاقات عامة لتعيين طلبات الطواقم',
    ur: 'عملے کی درخواستیں مقرر کرنے کے لیے پی آر صارف',
    hi: 'क्रू अनुरोध सौंपने के लिए पीआर उपयोगकर्ता',
  );
  static const chkPrNone = _T(
    en: 'None — Admin receives crew requests instead',
    ar: 'لا يوجد — يتلقى المسؤول طلبات الطواقم بدلًا من ذلك',
    ur: 'کوئی نہیں — اس کے بجائے ایڈمن کو درخواستیں ملتی ہیں',
    hi: 'कोई नहीं — इसके बजाय एडमिन को अनुरोध मिलते हैं',
  );
  static const chkFolders = _T(
    en: 'Default BOQ folders',
    ar: 'مجلدات جدول الكميات الافتراضية',
    ur: 'ڈیفالٹ BOQ فولڈر',
    hi: 'डिफ़ॉल्ट BOQ फ़ोल्डर',
  );
  static const chkRentals = _T(
    en: 'Rental reminders',
    ar: 'تذكيرات الإيجار',
    ur: 'کرایے کی یاد دہانیاں',
    hi: 'किराया अनुस्मारक',
  );
  static const chkOk = _T(en: 'Done', ar: 'تم', ur: 'مکمل', hi: 'पूर्ण');
  static const fix = _T(
    en: 'Fix',
    ar: 'إصلاح',
    ur: 'درست کریں',
    hi: 'ठीक करें',
  );
  static const open = _T(en: 'Open', ar: 'فتح', ur: 'کھولیں', hi: 'खोलें');
  static const allGood = _T(
    en: 'Everything is set up.',
    ar: 'تم إعداد كل شيء.',
    ur: 'سب کچھ ترتیب دیا جا چکا ہے۔',
    hi: 'सब कुछ सेट है।',
  );

  // ─── Company ───────────────────────────────────────────────────────────────
  static const grpNames = _T(en: 'Names', ar: 'الأسماء', ur: 'نام', hi: 'नाम');
  static const grpContact = _T(
    en: 'Contact and tax',
    ar: 'التواصل والضريبة',
    ur: 'رابطہ اور ٹیکس',
    hi: 'संपर्क और कर',
  );
  static const grpBank = _T(
    en: 'Bank (printed on invoices)',
    ar: 'البنك (يُطبع على الفواتير)',
    ur: 'بینک (انوائسز پر چھپتا ہے)',
    hi: 'बैंक (चालान पर छपता है)',
  );
  static const grpSupport = _T(
    en: 'App support',
    ar: 'دعم التطبيق',
    ur: 'ایپ سپورٹ',
    hi: 'ऐप सहायता',
  );
  static const grpFacts = _T(
    en: 'Fixed for this company',
    ar: 'ثابتة لهذه الشركة',
    ur: 'اس کمپنی کے لیے مقرر',
    hi: 'इस कंपनी के लिए तय',
  );
  static const grpPreview = _T(
    en: 'Letterhead preview',
    ar: 'معاينة الترويسة',
    ur: 'لیٹر ہیڈ کا پیش منظر',
    hi: 'लेटरहेड पूर्वावलोकन',
  );
  static const previewSub = _T(
    en: 'As new invoices and reports will print it',
    ar: 'كما ستطبعها الفواتير والتقارير الجديدة',
    ur: 'جیسے نئی انوائسز اور رپورٹس اسے چھاپیں گی',
    hi: 'जैसा नए चालान और रिपोर्ट इसे छापेंगे',
  );
  static const fLegalName = _T(
    en: 'Legal name',
    ar: 'الاسم القانوني',
    ur: 'قانونی نام',
    hi: 'कानूनी नाम',
  );
  static const fShortName = _T(
    en: 'Short name',
    ar: 'الاسم المختصر',
    ur: 'مختصر نام',
    hi: 'छोटा नाम',
  );
  static const fArabicName = _T(
    en: 'Arabic name',
    ar: 'الاسم العربي',
    ur: 'عربی نام',
    hi: 'अरबी नाम',
  );
  static const fAddress = _T(
    en: 'Address',
    ar: 'العنوان',
    ur: 'پتہ',
    hi: 'पता',
  );
  static const fPhone = _T(en: 'Phone', ar: 'الهاتف', ur: 'فون', hi: 'फ़ोन');
  static const fFax = _T(en: 'Fax', ar: 'الفاكس', ur: 'فیکس', hi: 'फ़ैक्स');
  static const fEmail = _T(
    en: 'Email',
    ar: 'البريد الإلكتروني',
    ur: 'ای میل',
    hi: 'ईमेल',
  );
  static const fTrn = _T(en: 'TRN', ar: 'الرقم الضريبي', ur: 'TRN', hi: 'TRN');
  static const fBankName = _T(
    en: 'Bank name',
    ar: 'اسم البنك',
    ur: 'بینک کا نام',
    hi: 'बैंक का नाम',
  );
  static const fAccountName = _T(
    en: 'Account name',
    ar: 'اسم الحساب',
    ur: 'اکاؤنٹ کا نام',
    hi: 'खाते का नाम',
  );
  static const fIban = _T(en: 'IBAN', ar: 'الآيبان', ur: 'IBAN', hi: 'IBAN');
  static const fWhatsapp = _T(
    en: 'Support WhatsApp',
    ar: 'واتساب الدعم',
    ur: 'سپورٹ واٹس ایپ',
    hi: 'सहायता व्हाट्सऐप',
  );
  static const fCurrency = _T(
    en: 'Currency',
    ar: 'العملة',
    ur: 'کرنسی',
    hi: 'मुद्रा',
  );
  static const fTimezone = _T(
    en: 'Time zone',
    ar: 'المنطقة الزمنية',
    ur: 'ٹائم زون',
    hi: 'समय क्षेत्र',
  );
  static const fWorkspace = _T(
    en: 'Workspace name',
    ar: 'اسم مساحة العمل',
    ur: 'ورک اسپیس کا نام',
    hi: 'वर्कस्पेस नाम',
  );
  static const fFileTypes = _T(
    en: 'Document file types',
    ar: 'أنواع ملفات المستندات',
    ur: 'دستاویز فائل کی اقسام',
    hi: 'दस्तावेज़ फ़ाइल प्रकार',
  );
  static const fFileSize = _T(
    en: 'Largest file',
    ar: 'أكبر حجم للملف',
    ur: 'سب سے بڑی فائل',
    hi: 'सबसे बड़ी फ़ाइल',
  );

  // ─── Lists ─────────────────────────────────────────────────────────────────
  static const add = _T(en: 'Add', ar: 'إضافة', ur: 'شامل کریں', hi: 'जोड़ें');
  static const rename = _T(
    en: 'Rename',
    ar: 'إعادة تسمية',
    ur: 'نام بدلیں',
    hi: 'नाम बदलें',
  );
  static const archive = _T(
    en: 'Archive',
    ar: 'أرشفة',
    ur: 'آرکائیو کریں',
    hi: 'संग्रहित करें',
  );
  static const restore = _T(
    en: 'Restore',
    ar: 'استعادة',
    ur: 'بحال کریں',
    hi: 'पुनर्स्थापित करें',
  );
  static const archived = _T(
    en: 'Archived',
    ar: 'مؤرشف',
    ur: 'آرکائیو شدہ',
    hi: 'संग्रहित',
  );
  static const system = _T(
    en: 'Built in',
    ar: 'مدمج',
    ur: 'بلٹ اِن',
    hi: 'अंतर्निहित',
  );
  static const newName = _T(en: 'Name', ar: 'الاسم', ur: 'نام', hi: 'नाम');
  static const moveUp = _T(
    en: 'Move up',
    ar: 'تحريك لأعلى',
    ur: 'اوپر کریں',
    hi: 'ऊपर करें',
  );
  static const moveDown = _T(
    en: 'Move down',
    ar: 'تحريك لأسفل',
    ur: 'نیچے کریں',
    hi: 'नीचे करें',
  );
  static const usedBy = _T(
    en: 'In {n} folders',
    ar: 'في {n} مجلدات',
    ur: '{n} فولڈرز میں',
    hi: '{n} फ़ोल्डरों में',
  );
  static const showArchived = _T(
    en: 'Show archived ({n})',
    ar: 'إظهار المؤرشف ({n})',
    ur: 'آرکائیو شدہ دکھائیں ({n})',
    hi: 'संग्रहित दिखाएँ ({n})',
  );
  static const newItem = _T(en: 'new', ar: 'جديد', ur: 'نیا', hi: 'नया');

  // ─── Projects ──────────────────────────────────────────────────────────────
  static const foldersTitle = _T(
    en: 'Default folders',
    ar: 'المجلدات الافتراضية',
    ur: 'ڈیفالٹ فولڈر',
    hi: 'डिफ़ॉल्ट फ़ोल्डर',
  );
  static const foldersHow = _T(
    en: 'Every new building and Common scope starts with the folders that are on, in this order. Existing folders are never changed; each project can rename or archive its own.',
    ar: 'يبدأ كل مبنى جديد ونطاق مشترك بالمجلدات المفعّلة بهذا الترتيب. لا تتغير المجلدات الموجودة أبدًا؛ ويمكن لكل مشروع إعادة تسمية مجلداته أو أرشفتها.',
    ur: 'ہر نئی عمارت اور کامن اسکوپ آن فولڈرز سے اسی ترتیب میں شروع ہوتا ہے۔ موجودہ فولڈر کبھی نہیں بدلتے؛ ہر پروجیکٹ اپنے فولڈر کا نام بدل یا آرکائیو کر سکتا ہے۔',
    hi: 'हर नई इमारत और कॉमन स्कोप चालू फ़ोल्डरों से इसी क्रम में शुरू होता है। मौजूदा फ़ोल्डर कभी नहीं बदलते; हर प्रोजेक्ट अपने फ़ोल्डर का नाम बदल या संग्रहित कर सकता है।',
  );
  static const newFolder = _T(
    en: 'New folder name',
    ar: 'اسم المجلد الجديد',
    ur: 'نئے فولڈر کا نام',
    hi: 'नए फ़ोल्डर का नाम',
  );

  // ─── Requests ──────────────────────────────────────────────────────────────
  static const rulesTitle = _T(
    en: 'Request rules',
    ar: 'قواعد الطلبات',
    ur: 'درخواست کے اصول',
    hi: 'अनुरोध नियम',
  );
  static const defaultTiming = _T(
    en: 'New requests start as',
    ar: 'تبدأ الطلبات الجديدة كـ',
    ur: 'نئی درخواستیں شروع ہوتی ہیں بطور',
    hi: 'नए अनुरोध शुरू होते हैं',
  );
  static const timingNormal = _T(
    en: 'Normal',
    ar: 'عادي',
    ur: 'معمول',
    hi: 'सामान्य',
  );
  static const timingUrgent = _T(
    en: 'Urgent',
    ar: 'عاجل',
    ur: 'فوری',
    hi: 'तत्काल',
  );
  static const urgentAllowed = _T(
    en: 'Allow urgent requests',
    ar: 'السماح بالطلبات العاجلة',
    ur: 'فوری درخواستوں کی اجازت',
    hi: 'तत्काल अनुरोधों की अनुमति',
  );
  static const urgentAllowedHint = _T(
    en: 'When off, nobody can submit a request marked urgent.',
    ar: 'عند الإيقاف لا يمكن لأحد إرسال طلب عاجل.',
    ur: 'آف ہونے پر کوئی فوری درخواست جمع نہیں کر سکتا۔',
    hi: 'बंद होने पर कोई तत्काल अनुरोध जमा नहीं कर सकता।',
  );
  static const selfApproval = _T(
    en: 'A Project Engineer may approve their own request',
    ar: 'يجوز لمهندس المشروع اعتماد طلبه',
    ur: 'پروجیکٹ انجینئر اپنی درخواست منظور کر سکتا ہے',
    hi: 'प्रोजेक्ट इंजीनियर अपना अनुरोध स्वीकृत कर सकता है',
  );
  static const selfApprovalHint = _T(
    en: 'When off, another approver must approve it.',
    ar: 'عند الإيقاف يجب أن يعتمده شخص آخر.',
    ur: 'آف ہونے پر کسی اور منظور کنندہ کو منظور کرنا ہوگا۔',
    hi: 'बंद होने पर किसी अन्य स्वीकृतकर्ता को स्वीकृत करना होगा।',
  );
  static const mrCategories = _T(
    en: 'Company request categories',
    ar: 'فئات طلبات الشركة',
    ur: 'کمپنی درخواست کے زمرے',
    hi: 'कंपनी अनुरोध श्रेणियाँ',
  );
  static const mrDepartments = _T(
    en: 'Departments',
    ar: 'الأقسام',
    ur: 'شعبے',
    hi: 'विभाग',
  );

  // ─── Inventory ─────────────────────────────────────────────────────────────
  static const sourcingTitle = _T(
    en: 'Sourcing',
    ar: 'التوريد',
    ur: 'سورسنگ',
    hi: 'सोर्सिंग',
  );
  static const externalReadiness = _T(
    en: 'Supplier source must be ready before arranging',
    ar: 'يجب تجهيز مصدر المورّد قبل الترتيب',
    ur: 'ترتیب سے پہلے سپلائر ذریعہ تیار ہونا چاہیے',
    hi: 'व्यवस्था से पहले आपूर्तिकर्ता स्रोत तैयार होना चाहिए',
  );
  static const externalReadinessHint = _T(
    en: 'When on, Procurement records the supplier and expected date for lines not supplied from the warehouse.',
    ar: 'عند التشغيل يسجّل قسم المشتريات المورد والتاريخ المتوقع للبنود غير الموردة من المستودع.',
    ur: 'آن ہونے پر خریداری گودام سے فراہم نہ ہونے والی لائنوں کے لیے سپلائر اور متوقع تاریخ درج کرتی ہے۔',
    hi: 'चालू होने पर खरीद विभाग गोदाम से न दी गई पंक्तियों के लिए आपूर्तिकर्ता और अपेक्षित तिथि दर्ज करता है।',
  );
  static const warehouseFirst = _T(
    en: 'The warehouse is always checked first',
    ar: 'يُفحص المستودع دائمًا أولًا',
    ur: 'گودام ہمیشہ پہلے دیکھا جاتا ہے',
    hi: 'गोदाम हमेशा पहले जाँचा जाता है',
  );
  static const categoriesTitle = _T(
    en: 'Inventory categories',
    ar: 'فئات المخزون',
    ur: 'انوینٹری زمرے',
    hi: 'इन्वेंट्री श्रेणियाँ',
  );
  static const aliases = _T(
    en: 'Also known as',
    ar: 'تُعرف أيضًا باسم',
    ur: 'دوسرا نام',
    hi: 'अन्य नाम',
  );
  static const addAlias = _T(
    en: 'Add another name',
    ar: 'أضف اسمًا آخر',
    ur: 'دوسرا نام شامل کریں',
    hi: 'अन्य नाम जोड़ें',
  );
  static const unitsTitle = _T(
    en: 'Units',
    ar: 'الوحدات',
    ur: 'اکائیاں',
    hi: 'इकाइयाँ',
  );
  static const unitCode = _T(
    en: 'Short code',
    ar: 'الرمز المختصر',
    ur: 'مختصر کوڈ',
    hi: 'छोटा कोड',
  );
  static const unitType = _T(en: 'Type', ar: 'النوع', ur: 'قسم', hi: 'प्रकार');
  static const unitDecimals = _T(
    en: 'Decimals',
    ar: 'المنازل العشرية',
    ur: 'اعشاریہ',
    hi: 'दशमलव',
  );

  // ─── Accounts ──────────────────────────────────────────────────────────────
  static const policyTitle = _T(
    en: 'Default payment policy',
    ar: 'سياسة الدفع الافتراضية',
    ur: 'ڈیفالٹ ادائیگی پالیسی',
    hi: 'डिफ़ॉल्ट भुगतान नीति',
  );
  static const paymentTerms = _T(
    en: 'Payment terms (days)',
    ar: 'شروط الدفع (أيام)',
    ur: 'ادائیگی کی شرائط (دن)',
    hi: 'भुगतान शर्तें (दिन)',
  );
  static const reminderLead = _T(
    en: 'Remind before due (days)',
    ar: 'التذكير قبل الاستحقاق (أيام)',
    ur: 'واجب الادا سے پہلے یاد دہانی (دن)',
    hi: 'देय से पहले अनुस्मारक (दिन)',
  );
  static const stagesTitle = _T(
    en: 'Default billing stages',
    ar: 'مراحل الفوترة الافتراضية',
    ur: 'ڈیفالٹ بلنگ مراحل',
    hi: 'डिफ़ॉल्ट बिलिंग चरण',
  );
  static const stagesHow = _T(
    en: 'New project baselines start with these stages. Existing projects keep theirs.',
    ar: 'تبدأ خطوط الأساس للمشاريع الجديدة بهذه المراحل. وتحتفظ المشاريع الحالية بمراحلها.',
    ur: 'نئے پروجیکٹ بیس لائنز ان مراحل سے شروع ہوتی ہیں۔ موجودہ پروجیکٹس اپنے مراحل رکھتے ہیں۔',
    hi: 'नए प्रोजेक्ट बेसलाइन इन चरणों से शुरू होते हैं। मौजूदा प्रोजेक्ट अपने चरण रखते हैं।',
  );
  static const stageName = _T(
    en: 'Stage',
    ar: 'المرحلة',
    ur: 'مرحلہ',
    hi: 'चरण',
  );
  static const stagePercent = _T(
    en: 'Share %',
    ar: 'النسبة %',
    ur: 'حصہ %',
    hi: 'हिस्सा %',
  );
  static const addStage = _T(
    en: 'Add stage',
    ar: 'إضافة مرحلة',
    ur: 'مرحلہ شامل کریں',
    hi: 'चरण जोड़ें',
  );
  static const total = _T(
    en: 'Total {p}%',
    ar: 'الإجمالي {p}%',
    ur: 'کل {p}%',
    hi: 'कुल {p}%',
  );

  // ─── Workforce, rentals, notifications, access, numbering ──────────────────
  static const holidays = _T(
    en: 'Public holidays',
    ar: 'العطلات الرسمية',
    ur: 'سرکاری چھٹیاں',
    hi: 'सार्वजनिक छुट्टियाँ',
  );
  static const holidaysHint = _T(
    en: 'Work on these days counts as holiday overtime.',
    ar: 'يُحتسب العمل في هذه الأيام عملًا إضافيًا في العطلة.',
    ur: 'ان دنوں کا کام چھٹی کا اوور ٹائم شمار ہوتا ہے۔',
    hi: 'इन दिनों का काम छुट्टी का ओवरटाइम गिना जाता है।',
  );
  static const offDaysTitle = _T(
    en: 'Weekly off days',
    ar: 'أيام العطلة الأسبوعية',
    ur: 'ہفتہ وار چھٹی کے دن',
    hi: 'साप्ताहिक अवकाश के दिन',
  );
  static const offDaysHint = _T(
    en: 'Work on these days counts as holiday overtime, like public holidays. Days already saved keep their hours.',
    ar: 'يُحتسب العمل في هذه الأيام عملًا إضافيًا في العطلة مثل العطلات الرسمية. تحتفظ الأيام المحفوظة بساعاتها.',
    ur: 'ان دنوں کا کام سرکاری چھٹیوں کی طرح چھٹی کا اوور ٹائم شمار ہوتا ہے۔ محفوظ شدہ دن اپنے گھنٹے رکھتے ہیں۔',
    hi: 'इन दिनों का काम सार्वजनिक छुट्टियों की तरह छुट्टी का ओवरटाइम गिना जाता है। सहेजे गए दिन अपने घंटे रखते हैं।',
  );
  static const weekdays = <String, TranslatableString>{
    'monday': _T(en: 'Mon', ar: 'الإثنين', ur: 'پیر', hi: 'सोम'),
    'tuesday': _T(en: 'Tue', ar: 'الثلاثاء', ur: 'منگل', hi: 'मंगल'),
    'wednesday': _T(en: 'Wed', ar: 'الأربعاء', ur: 'بدھ', hi: 'बुध'),
    'thursday': _T(en: 'Thu', ar: 'الخميس', ur: 'جمعرات', hi: 'गुरु'),
    'friday': _T(en: 'Fri', ar: 'الجمعة', ur: 'جمعہ', hi: 'शुक्र'),
    'saturday': _T(en: 'Sat', ar: 'السبت', ur: 'ہفتہ', hi: 'शनि'),
    'sunday': _T(en: 'Sun', ar: 'الأحد', ur: 'اتوار', hi: 'रवि'),
  };
  static const shiftsLocations = _T(
    en: 'Shifts, internal locations and trades',
    ar: 'الورديات والمواقع الداخلية والمهن',
    ur: 'شفٹیں، اندرونی مقامات اور ہنر',
    hi: 'शिफ़्ट, आंतरिक स्थान और ट्रेड',
  );
  static const shiftsLocationsHint = _T(
    en: 'Used when creating crews and recording attendance.',
    ar: 'تُستخدم عند إنشاء الطواقم وتسجيل الحضور.',
    ur: 'عملے بنانے اور حاضری درج کرنے میں استعمال ہوتے ہیں۔',
    hi: 'क्रू बनाने और उपस्थिति दर्ज करने में उपयोग होते हैं।',
  );
  static const crewsLink = _T(
    en: 'Crews and their usual shift',
    ar: 'الطواقم وورديتها المعتادة',
    ur: 'عملے اور ان کی معمول کی شفٹ',
    hi: 'क्रू और उनकी सामान्य शिफ़्ट',
  );
  static const rentalsEnabled = _T(
    en: 'Send rental reminders',
    ar: 'إرسال تذكيرات الإيجار',
    ur: 'کرایے کی یاد دہانیاں بھیجیں',
    hi: 'किराया अनुस्मारक भेजें',
  );
  static const rentalsEnabledHint = _T(
    en: 'Renewal windows, expired leases, cheques due and rent overdue, to Admin and PR.',
    ar: 'نوافذ التجديد والعقود المنتهية والشيكات المستحقة والإيجار المتأخر، إلى المسؤول والعلاقات العامة.',
    ur: 'تجدید کی مدت، ختم شدہ لیز، واجب چیک اور بقایا کرایہ، ایڈمن اور پی آر کو۔',
    hi: 'नवीनीकरण अवधि, समाप्त लीज़, देय चेक और बकाया किराया, एडमिन और पीआर को।',
  );
  static const rentalsPush = _T(
    en: 'Also as phone and browser alerts',
    ar: 'وأيضًا كتنبيهات على الهاتف والمتصفح',
    ur: 'فون اور براؤزر الرٹس کے طور پر بھی',
    hi: 'फ़ोन और ब्राउज़र अलर्ट के रूप में भी',
  );
  static const rentalsPushHint = _T(
    en: 'When off, reminders only appear in the app inbox. A new recipient never receives a burst of old reminders.',
    ar: 'عند الإيقاف تظهر التذكيرات في صندوق التطبيق فقط. لا يتلقى المستلم الجديد دفعة من التذكيرات القديمة.',
    ur: 'آف ہونے پر یاد دہانیاں صرف ایپ ان باکس میں آتی ہیں۔ نئے وصول کنندہ کو پرانی یاد دہانیوں کا ڈھیر کبھی نہیں ملتا۔',
    hi: 'बंद होने पर अनुस्मारक केवल ऐप इनबॉक्स में आते हैं। नए प्राप्तकर्ता को पुराने अनुस्मारकों का ढेर कभी नहीं मिलता।',
  );
  static const lastRun = _T(
    en: 'Last checked {at}',
    ar: 'آخر فحص {at}',
    ur: 'آخری جانچ {at}',
    hi: 'अंतिम जाँच {at}',
  );
  static const pushEnabled = _T(
    en: 'Phone and browser alerts',
    ar: 'تنبيهات الهاتف والمتصفح',
    ur: 'فون اور براؤزر الرٹس',
    hi: 'फ़ोन और ब्राउज़र अलर्ट',
  );
  static const pushEnabledHint = _T(
    en: 'When off, notifications stay in the app inbox only, for everyone.',
    ar: 'عند الإيقاف تبقى الإشعارات في صندوق التطبيق فقط للجميع.',
    ur: 'آف ہونے پر سب کے لیے اطلاعات صرف ایپ ان باکس میں رہتی ہیں۔',
    hi: 'बंद होने पर सभी के लिए सूचनाएँ केवल ऐप इनबॉक्स में रहती हैं।',
  );
  static const dailyReminders = _T(
    en: 'Daily reminders',
    ar: 'التذكيرات اليومية',
    ur: 'روزانہ یاد دہانیاں',
    hi: 'दैनिक अनुस्मारक',
  );
  static const remMonthEnd = _T(
    en: 'Attendance months to confirm — 8:05 AM',
    ar: 'أشهر الحضور المطلوب تأكيدها — 8:05 ص',
    ur: 'تصدیق طلب حاضری کے مہینے — صبح 8:05',
    hi: 'पुष्टि हेतु उपस्थिति माह — सुबह 8:05',
  );
  static const remCrewRequests = _T(
    en: 'Crew requests waiting for workers — 8:10 AM',
    ar: 'طلبات طواقم بانتظار العمال — 8:10 ص',
    ur: 'کارکنوں کی منتظر عملے کی درخواستیں — صبح 8:10',
    hi: 'कामगारों की प्रतीक्षा में क्रू अनुरोध — सुबह 8:10',
  );
  static const remRentals = _T(
    en: 'Rental reminders — checked every hour',
    ar: 'تذكيرات الإيجار — تُفحص كل ساعة',
    ur: 'کرایے کی یاد دہانیاں — ہر گھنٹے جانچ',
    hi: 'किराया अनुस्मारक — हर घंटे जाँच',
  );
  static const usersLink = _T(
    en: 'Users and their roles',
    ar: 'المستخدمون وأدوارهم',
    ur: 'صارفین اور ان کے کردار',
    hi: 'उपयोगकर्ता और उनकी भूमिकाएँ',
  );
  static const usersLinkHint = _T(
    en: 'Add people, change roles, project access and individual permissions.',
    ar: 'أضف أشخاصًا وغيّر الأدوار والوصول للمشاريع والصلاحيات الفردية.',
    ur: 'لوگ شامل کریں، کردار، پروجیکٹ رسائی اور انفرادی اجازتیں بدلیں۔',
    hi: 'लोग जोड़ें, भूमिकाएँ, प्रोजेक्ट पहुँच और व्यक्तिगत अनुमतियाँ बदलें।',
  );
  static const signInRules = _T(
    en: 'Sign-in rules',
    ar: 'قواعد تسجيل الدخول',
    ur: 'سائن ان کے اصول',
    hi: 'साइन-इन नियम',
  );
  static const signInRulesBody = _T(
    en: 'Passwords, sessions and two-step sign-in are managed by the sign-in service, not here. Every access change and export is always recorded in the Audit Trail.',
    ar: 'تُدار كلمات المرور والجلسات والتحقق بخطوتين من خدمة تسجيل الدخول وليس من هنا. ويُسجَّل كل تغيير في الوصول وكل تصدير دائمًا في سجل التدقيق.',
    ur: 'پاس ورڈ، سیشن اور دو مرحلہ سائن ان، سائن ان سروس سنبھالتی ہے، یہاں نہیں۔ ہر رسائی کی تبدیلی اور برآمد ہمیشہ آڈٹ ٹریل میں درج ہوتی ہے۔',
    hi: 'पासवर्ड, सत्र और दो-चरणीय साइन-इन साइन-इन सेवा संभालती है, यहाँ नहीं। हर पहुँच परिवर्तन और निर्यात हमेशा ऑडिट ट्रेल में दर्ज होता है।',
  );
  static const numberingHow = _T(
    en: 'Numbers are given by the server when a record is created and never reused.',
    ar: 'يمنح الخادم الأرقام عند إنشاء السجل ولا تُعاد أبدًا.',
    ur: 'نمبر ریکارڈ بنتے وقت سرور دیتا ہے اور کبھی دوبارہ استعمال نہیں ہوتے۔',
    hi: 'संख्या रिकॉर्ड बनते समय सर्वर देता है और कभी दोबारा उपयोग नहीं होती।',
  );
  static const numMr = _T(
    en: 'Material request',
    ar: 'طلب مواد',
    ur: 'مواد کی درخواست',
    hi: 'सामग्री अनुरोध',
  );
  static const numDispatch = _T(
    en: 'Dispatch / Delivery Order',
    ar: 'إرسالية / أمر تسليم',
    ur: 'ڈسپیچ / ڈلیوری آرڈر',
    hi: 'प्रेषण / डिलीवरी ऑर्डर',
  );
  static const numReturn = _T(
    en: 'Material return',
    ar: 'إرجاع مواد',
    ur: 'مواد کی واپسی',
    hi: 'सामग्री वापसी',
  );
  static const numInvoice = _T(
    en: 'Invoice',
    ar: 'فاتورة',
    ur: 'انوائس',
    hi: 'चालान',
  );
  static const numCrewRequest = _T(
    en: 'Crew request',
    ar: 'طلب طاقم',
    ur: 'عملے کی درخواست',
    hi: 'क्रू अनुरोध',
  );
  static const numProject = _T(
    en: 'Project',
    ar: 'مشروع',
    ur: 'پروجیکٹ',
    hi: 'प्रोजेक्ट',
  );
  static const numProjectValue = _T(
    en: 'Reference chosen when the project is created, unique',
    ar: 'مرجع يُختار عند إنشاء المشروع، فريد',
    ur: 'پروجیکٹ بناتے وقت منتخب کردہ منفرد حوالہ',
    hi: 'प्रोजेक्ट बनाते समय चुना गया अद्वितीय संदर्भ',
  );
  static const example = _T(
    en: 'e.g. {x}',
    ar: 'مثال {x}',
    ur: 'مثلاً {x}',
    hi: 'उदा. {x}',
  );
  static const historyEmpty = _T(
    en: 'No changes saved yet.',
    ar: 'لم تُحفظ أي تغييرات بعد.',
    ur: 'ابھی کوئی تبدیلی محفوظ نہیں ہوئی۔',
    hi: 'अभी कोई बदलाव सहेजा नहीं गया।',
  );
  static const historyLine = _T(
    en: '{who} · {when} · {n} changes',
    ar: '{who} · {when} · {n} تغييرات',
    ur: '{who} · {when} · {n} تبدیلیاں',
    hi: '{who} · {when} · {n} बदलाव',
  );
}
