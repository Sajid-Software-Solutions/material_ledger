import 'app_strings.dart';

/// Centralized, bilingual-capable copy for the Yorks V1 BOQ workspace.
abstract final class YorksV1BoqStrings {
  static const page = TranslatableString(
    en: 'Page',
    ar: 'صفحة',
    ur: 'صفحہ',
    hi: 'पृष्ठ',
  );
  static const of = TranslatableString(
    en: 'of',
    ar: 'من',
    ur: 'از',
    hi: 'में से',
  );
  static const printBoq = TranslatableString(
    en: 'Print BOQ',
    ar: 'طباعة جدول الكميات',
    ur: 'BOQ پرنٹ کریں',
    hi: 'BOQ प्रिंट करें',
  );
  static const printFailed = TranslatableString(
    en: 'The BOQ print view could not be prepared.',
    ar: 'تعذر إعداد عرض طباعة جدول الكميات.',
    ur: 'BOQ پرنٹ ویو تیار نہیں ہو سکا۔',
    hi: 'BOQ प्रिंट दृश्य तैयार नहीं हो सका।',
  );
  static const serialNumber = TranslatableString(
    en: 'S:No',
    ar: 'م',
    ur: 'نمبر',
    hi: 'क्र.',
  );
  static const boq = TranslatableString(
    en: 'Bill of quantities',
    ar: 'جدول الكميات',
    ur: 'بل آف کوانٹٹیز',
    hi: 'मात्रा विवरण',
  );
  static const boqDescription = TranslatableString(
    en: 'Organise each project worksheet, then edit material rows directly.',
    ar: 'نظّم كل ورقة عمل للمشروع ثم عدّل صفوف المواد مباشرة.',
    ur: 'ہر پراجیکٹ ورک شیٹ منظم کریں اور میٹریل قطاریں براہ راست ایڈٹ کریں۔',
    hi: 'प्रोजेक्ट वर्कशीट व्यवस्थित करें और सामग्री पंक्तियाँ सीधे संपादित करें।',
  );
  static const worksheets = TranslatableString(
    en: 'BOQ worksheets',
    ar: 'أوراق عمل جدول الكميات',
    ur: 'BOQ ورک شیٹس',
    hi: 'BOQ वर्कशीट',
  );
  static const workspaceTitle = TranslatableString(
    en: 'BOQ',
    ar: 'جدول الكميات',
    ur: 'BOQ',
    hi: 'BOQ',
  );
  static const groupsAndWorksheets = TranslatableString(
    en: 'BOQ groups & worksheets',
    ar: 'مجموعات وأوراق عمل جدول الكميات',
    ur: 'BOQ گروپس اور ورک شیٹس',
    hi: 'BOQ समूह और वर्कशीट',
  );
  static const searchGroups = TranslatableString(
    en: 'Search groups or worksheets…',
    ar: 'ابحث في المجموعات أو أوراق العمل…',
    ur: 'گروپس یا ورک شیٹس تلاش کریں…',
    hi: 'समूह या वर्कशीट खोजें…',
  );
  static const notStartedStatus = TranslatableString(
    en: 'Not started',
    ar: 'لم يبدأ',
    ur: 'شروع نہیں ہوا',
    hi: 'शुरू नहीं हुआ',
  );
  static const sortLastEdited = TranslatableString(
    en: 'Sort by: Last edited',
    ar: 'الترتيب حسب: آخر تعديل',
    ur: 'ترتیب: آخری ترمیم',
    hi: 'क्रम: अंतिम संपादन',
  );
  static const buildingsAndScopes = TranslatableString(
    en: 'Buildings / scopes',
    ar: 'المباني / النطاقات',
    ur: 'بلڈنگز / اسکوپس',
    hi: 'बिल्डिंग / स्कोप',
  );
  static const groupsMetric = TranslatableString(
    en: 'BOQ groups',
    ar: 'مجموعات جدول الكميات',
    ur: 'BOQ گروپس',
    hi: 'BOQ समूह',
  );
  static const materialRowsMetric = TranslatableString(
    en: 'Material rows',
    ar: 'صفوف المواد',
    ur: 'میٹریل قطاریں',
    hi: 'सामग्री पंक्तियाँ',
  );
  static const recentGroups = TranslatableString(
    en: 'Recent BOQ groups',
    ar: 'مجموعات جدول الكميات الحديثة',
    ur: 'حالیہ BOQ گروپس',
    hi: 'हाल के BOQ समूह',
  );
  static const groupName = TranslatableString(
    en: 'Group name',
    ar: 'اسم المجموعة',
    ur: 'گروپ کا نام',
    hi: 'समूह का नाम',
  );
  static const editedBy = TranslatableString(
    en: 'Edited by',
    ar: 'عدّله',
    ur: 'ایڈٹ کرنے والا',
    hi: 'संपादक',
  );
  static const scope = TranslatableString(
    en: 'BOQ scope',
    ar: 'نطاق جدول الكميات',
    ur: 'BOQ اسکوپ',
    hi: 'BOQ स्कोप',
  );
  static const allScopes = TranslatableString(
    en: 'Overview',
    ar: 'نظرة عامة',
    ur: 'جائزہ',
    hi: 'अवलोकन',
  );
  static const allScopesDescription = TranslatableString(
    en: 'Read-only aggregate of Common and every building. Choose one scope to edit, export or create a material request source.',
    ar: 'عرض مجمع للقراءة فقط للنطاق المشترك وجميع المباني. اختر نطاقاً واحداً للتعديل أو التصدير أو إنشاء مصدر لطلب مواد.',
    ur: 'کامن اور ہر بلڈنگ کا صرف پڑھنے کے لیے مجموعی منظر۔ ایڈٹ، ایکسپورٹ یا میٹریل ریکویسٹ سورس کے لیے ایک اسکوپ منتخب کریں۔',
    hi: 'कॉमन और हर बिल्डिंग का केवल-पढ़ने योग्य समेकित दृश्य। संपादन, निर्यात या सामग्री अनुरोध स्रोत के लिए एक स्कोप चुनें।',
  );
  static const overviewDescription = TranslatableString(
    en: 'Project overview only. Each Common/building BOQ remains independent and keeps its own folders, rows, imports and material requests.',
    ar: 'نظرة عامة للمشروع فقط. يظل كل جدول كميات مشترك/مبنى مستقلاً ويحتفظ بمجلداته وصفوفه ووارداته وطلبات مواده الخاصة.',
    ur: 'صرف پراجیکٹ اوورویو۔ ہر کامن/بلڈنگ BOQ آزاد رہتا ہے اور اپنے فولڈرز، قطاریں، امپورٹس اور میٹیریل ریکویسٹس رکھتا ہے۔',
    hi: 'केवल प्रोजेक्ट अवलोकन। प्रत्येक कॉमन/बिल्डिंग BOQ स्वतंत्र रहता है और अपने फ़ोल्डर, पंक्तियाँ, आयात और सामग्री अनुरोध रखता है।',
  );
  static const folders = TranslatableString(
    en: 'Folders',
    ar: 'المجلدات',
    ur: 'فولڈرز',
    hi: 'फ़ोल्डर',
  );
  static const startedFolders = TranslatableString(
    en: 'Started',
    ar: 'بدأت',
    ur: 'شروع شدہ',
    hi: 'प्रारंभ किए गए',
  );
  static const materials = TranslatableString(
    en: 'Materials',
    ar: 'المواد',
    ur: 'میٹیریلز',
    hi: 'सामग्री',
  );
  static const openScope = TranslatableString(
    en: 'Open scope',
    ar: 'فتح النطاق',
    ur: 'اسکوپ کھولیں',
    hi: 'स्कोप खोलें',
  );
  static const allFolders = TranslatableString(
    en: 'All',
    ar: 'الكل',
    ur: 'تمام',
    hi: 'सभी',
  );
  static const emptyFolders = TranslatableString(
    en: 'Empty',
    ar: 'فارغة',
    ur: 'خالی',
    hi: 'खाली',
  );
  static const materialFolders = TranslatableString(
    en: 'Material folders',
    ar: 'مجلدات المواد',
    ur: 'میٹریل فولڈرز',
    hi: 'सामग्री फ़ोल्डर',
  );
  static const materialFoldersDescription = TranslatableString(
    en: 'Each folder owns its rows, imports, documents and linked requests.',
    ar: 'يمتلك كل مجلد صفوفه ووارداته ومستنداته وطلباته المرتبطة.',
    ur: 'ہر فولڈر اپنی قطاریں، امپورٹس، دستاویزات اور منسلک ریکوئسٹس رکھتا ہے۔',
    hi: 'हर फ़ोल्डर अपनी पंक्तियाँ, आयात, दस्तावेज़ और जुड़े अनुरोध रखता है।',
  );
  static const independentBoqTitle = TranslatableString(
    en: 'Every building has its own BOQ',
    ar: 'لكل مبنى جدول كميات مستقل',
    ur: 'ہر بلڈنگ کا اپنا BOQ ہے',
    hi: 'हर बिल्डिंग का अपना BOQ है',
  );
  static const independentBoqDescription = TranslatableString(
    en: 'Materials are never combined into one editable project list. Common remains genuinely shared.',
    ar: 'لا تُدمج المواد أبداً في قائمة مشروع واحدة قابلة للتعديل. يظل النطاق المشترك مشتركاً فعلياً.',
    ur: 'میٹریلز کو کبھی ایک قابل تدوین پراجیکٹ لسٹ میں جمع نہیں کیا جاتا۔ کامن حقیقی طور پر مشترک رہتا ہے۔',
    hi: 'सामग्री कभी एक संपादन योग्य प्रोजेक्ट सूची में नहीं मिलती। कॉमन वास्तव में साझा रहता है।',
  );
  static const legacyBoqs = TranslatableString(
    en: 'Legacy BOQs needing scope assignment',
    ar: 'جداول كميات قديمة تحتاج تعيين النطاق',
    ur: 'اسکوپ اسائنمنٹ کی ضرورت والے لیگیسی BOQs',
    hi: 'स्कोप असाइनमेंट आवश्यक वाले लीगेसी BOQ',
  );
  static const legacyUnassigned = TranslatableString(
    en: 'Legacy BOQ — scope assignment required',
    ar: 'جدول كميات قديم — يلزم تعيين النطاق',
    ur: 'لیگیسی BOQ — اسکوپ اسائنمنٹ درکار ہے',
    hi: 'लीगेसी BOQ — स्कोप असाइनमेंट आवश्यक है',
  );
  static const assignLegacyScope = TranslatableString(
    en: 'Assign BOQ scope',
    ar: 'تعيين نطاق جدول الكميات',
    ur: 'BOQ اسکوپ اسائن کریں',
    hi: 'BOQ स्कोप असाइन करें',
  );
  static const assignLegacyScopeDescription = TranslatableString(
    en: 'Choose the one real Common or building scope that owns this preserved BOQ. This cannot rewrite submitted request history.',
    ar: 'اختر النطاق الحقيقي الوحيد المشترك أو المبنى الذي يملك جدول الكميات المحفوظ. لا يمكن لهذا إعادة كتابة سجل الطلبات المُرسلة.',
    ur: 'وہ ایک اصلی کامن یا بلڈنگ اسکوپ منتخب کریں جس کا یہ محفوظ BOQ ہے۔ یہ جمع شدہ ریکویسٹ ہسٹری کو دوبارہ نہیں لکھ سکتا۔',
    hi: 'वह एक वास्तविक कॉमन या बिल्डिंग स्कोप चुनें जिसका यह संरक्षित BOQ है। यह सबमिट किए गए अनुरोध इतिहास को नहीं बदलेगा।',
  );
  static const scopedWorksheet = TranslatableString(
    en: 'Scope: {scope}',
    ar: 'النطاق: {scope}',
    ur: 'اسکوپ: {scope}',
    hi: 'स्कोप: {scope}',
  );
  static const addGroup = TranslatableString(
    en: 'Add custom group',
    ar: 'إضافة مجموعة مخصصة',
    ur: 'کسٹم گروپ شامل کریں',
    hi: 'कस्टम समूह जोड़ें',
  );
  static const newGroup = TranslatableString(
    en: 'New Group',
    ar: 'مجموعة جديدة',
    ur: 'نیا گروپ',
    hi: 'नया समूह',
  );
  static const customGroupName = TranslatableString(
    en: 'Folder name (this Common/building scope)',
    ar: 'اسم المجلد (لهذا النطاق المشترك/المبنى)',
    ur: 'فولڈر کا نام (اس کامن/بلڈنگ اسکوپ کے لیے)',
    hi: 'फ़ोल्डर का नाम (इस कॉमन/बिल्डिंग स्कोप के लिए)',
  );
  static const manageFolders = TranslatableString(
    en: 'Manage folders',
    ar: 'إدارة المجلدات',
    ur: 'فولڈرز کا انتظام',
    hi: 'फ़ोल्डर प्रबंधित करें',
  );
  static const manageFoldersDescription = TranslatableString(
    en: 'Names and lifecycle apply only to the selected Common or building scope.',
    ar: 'تسري الأسماء ودورة الحياة فقط على النطاق المشترك أو المبنى المحدد.',
    ur: 'نام اور لائف سائیکل صرف منتخب کامن یا بلڈنگ اسکوپ پر لاگو ہوتے ہیں۔',
    hi: 'नाम और जीवनचक्र केवल चुने हुए कॉमन या बिल्डिंग स्कोप पर लागू होते हैं।',
  );
  static const renameFolder = TranslatableString(
    en: 'Rename folder',
    ar: 'إعادة تسمية المجلد',
    ur: 'فولڈر کا نام تبدیل کریں',
    hi: 'फ़ोल्डर का नाम बदलें',
  );
  static const renameFolderDescription = TranslatableString(
    en: 'Only this scope changes. Rows, documents and linked requests keep their stable references.',
    ar: 'يتغير هذا النطاق فقط. تحتفظ الصفوف والمستندات والطلبات المرتبطة بمراجعها الثابتة.',
    ur: 'صرف یہ اسکوپ تبدیل ہوگا۔ قطاریں، دستاویزات اور لنک شدہ ریکویسٹ اپنے مستقل حوالہ جات رکھیں گے۔',
    hi: 'केवल यह स्कोप बदलेगा। पंक्तियाँ, दस्तावेज़ और लिंक किए गए अनुरोध अपने स्थिर संदर्भ रखेंगे।',
  );
  static const changeReason = TranslatableString(
    en: 'Reason for change',
    ar: 'سبب التغيير',
    ur: 'تبدیلی کی وجہ',
    hi: 'बदलाव का कारण',
  );
  static const reasonRequired = TranslatableString(
    en: 'Enter a short reason for the audit history.',
    ar: 'أدخل سبباً قصيراً لسجل التدقيق.',
    ur: 'آڈٹ ہسٹری کے لیے مختصر وجہ درج کریں۔',
    hi: 'ऑडिट इतिहास के लिए एक छोटा कारण दर्ज करें।',
  );
  static const folderNameRequired = TranslatableString(
    en: 'Enter a folder name.',
    ar: 'أدخل اسم المجلد.',
    ur: 'فولڈر کا نام درج کریں۔',
    hi: 'फ़ोल्डर का नाम दर्ज करें।',
  );
  static const folderNameUnchanged = TranslatableString(
    en: 'Enter a different folder name.',
    ar: 'أدخل اسماً مختلفاً للمجلد.',
    ur: 'فولڈر کا مختلف نام درج کریں۔',
    hi: 'फ़ोल्डर का अलग नाम दर्ज करें।',
  );
  static const editWorksheet = TranslatableString(
    en: 'Open worksheet',
    ar: 'فتح ورقة العمل',
    ur: 'ورک شیٹ کھولیں',
    hi: 'वर्कशीट खोलें',
  );
  static const activeFolders = TranslatableString(
    en: 'Active folders',
    ar: 'المجلدات النشطة',
    ur: 'فعال فولڈرز',
    hi: 'सक्रिय फ़ोल्डर',
  );
  static const archivedFolders = TranslatableString(
    en: 'Archived folders',
    ar: 'المجلدات المؤرشفة',
    ur: 'آرکائیو شدہ فولڈرز',
    hi: 'आर्काइव किए गए फ़ोल्डर',
  );
  static const restoreFolder = TranslatableString(
    en: 'Restore folder',
    ar: 'استعادة المجلد',
    ur: 'فولڈر بحال کریں',
    hi: 'फ़ोल्डर पुनर्स्थापित करें',
  );
  static const restoreFolderDescription = TranslatableString(
    en: 'Restore this folder to the selected scope. Its retained worksheet and links become active again.',
    ar: 'استعد هذا المجلد إلى النطاق المحدد. ستصبح ورقة العمل والروابط المحفوظة نشطة مرة أخرى.',
    ur: 'اس فولڈر کو منتخب اسکوپ میں بحال کریں۔ اس کی محفوظ ورک شیٹ اور لنکس دوبارہ فعال ہو جائیں گے۔',
    hi: 'इस फ़ोल्डर को चुने हुए स्कोप में पुनर्स्थापित करें। इसकी सुरक्षित वर्कशीट और लिंक फिर सक्रिय होंगे।',
  );
  static const systemFolder = TranslatableString(
    en: 'Yorks template folder',
    ar: 'مجلد قالب يوركس',
    ur: 'یورکس ٹیمپلیٹ فولڈر',
    hi: 'Yorks टेम्पलेट फ़ोल्डर',
  );
  static const systemFolderCannotArchive = TranslatableString(
    en: 'Protected system folders can be renamed but not archived.',
    ar: 'يمكن إعادة تسمية مجلدات النظام المحمية ولكن لا يمكن أرشفتها.',
    ur: 'محفوظ سسٹم فولڈرز کا نام تبدیل کیا جا سکتا ہے لیکن انہیں آرکائیو نہیں کیا جا سکتا۔',
    hi: 'संरक्षित सिस्टम फ़ोल्डर का नाम बदला जा सकता है, लेकिन उन्हें आर्काइव नहीं किया जा सकता।',
  );
  static const lifecycleGuidance = TranslatableString(
    en: 'Whole-BOQ deletion is not available. Archive the project from Project settings when work is complete; Yorks keeps worksheets and linked request history.',
    ar: 'حذف جدول الكميات بالكامل غير متاح. أرشف المشروع من إعدادات المشروع عند اكتمال العمل؛ يحتفظ يوركس بأوراق العمل وسجل الطلبات المرتبطة.',
    ur: 'مکمل BOQ حذف کرنا دستیاب نہیں۔ کام مکمل ہونے پر پراجیکٹ سیٹنگز سے پراجیکٹ آرکائیو کریں؛ یورکس ورک شیٹس اور لنک شدہ ریکویسٹ ہسٹری محفوظ رکھتا ہے۔',
    hi: 'पूरा BOQ हटाना उपलब्ध नहीं है। काम पूरा होने पर प्रोजेक्ट सेटिंग्स से प्रोजेक्ट आर्काइव करें; Yorks वर्कशीट और लिंक अनुरोध इतिहास सुरक्षित रखता है।',
  );
  static const noGroups = TranslatableString(
    en: 'No BOQ worksheets are available for this project.',
    ar: 'لا توجد أوراق عمل جدول كميات متاحة لهذا المشروع.',
    ur: 'اس پراجیکٹ کے لیے کوئی BOQ ورک شیٹ دستیاب نہیں ہے۔',
    hi: 'इस प्रोजेक्ट के लिए कोई BOQ वर्कशीट उपलब्ध नहीं है।',
  );
  static const worksheet = TranslatableString(
    en: 'Worksheet',
    ar: 'ورقة العمل',
    ur: 'ورک شیٹ',
    hi: 'वर्कशीट',
  );
  static const worksheetTitle = TranslatableString(
    en: 'Worksheet title',
    ar: 'عنوان ورقة العمل',
    ur: 'ورک شیٹ کا عنوان',
    hi: 'वर्कशीट शीर्षक',
  );
  static const rows = TranslatableString(
    en: 'rows',
    ar: 'صفوف',
    ur: 'قطاریں',
    hi: 'पंक्तियाँ',
  );
  static const columns = TranslatableString(
    en: 'columns',
    ar: 'أعمدة',
    ur: 'کالم',
    hi: 'कॉलम',
  );
  static const defaultGroup = TranslatableString(
    en: 'Standard group',
    ar: 'مجموعة قياسية',
    ur: 'معیاری گروپ',
    hi: 'मानक समूह',
  );
  static const customGroup = TranslatableString(
    en: 'Custom group',
    ar: 'مجموعة مخصصة',
    ur: 'کسٹم گروپ',
    hi: 'कस्टम समूह',
  );
  static const addColumn = TranslatableString(
    en: 'Add column',
    ar: 'إضافة عمود',
    ur: 'کالم شامل کریں',
    hi: 'कॉलम जोड़ें',
  );
  static const columnHeading = TranslatableString(
    en: 'Column heading',
    ar: 'عنوان العمود',
    ur: 'کالم ہیڈنگ',
    hi: 'कॉलम शीर्षक',
  );
  static const blankRow = TranslatableString(
    en: 'Blank row',
    ar: 'صف فارغ',
    ur: 'خالی قطار',
    hi: 'खाली पंक्ति',
  );
  static const addRow = TranslatableString(
    en: 'Add row',
    ar: 'إضافة صف',
    ur: 'قطار شامل کریں',
    hi: 'पंक्ति जोड़ें',
  );
  static const pasteCells = TranslatableString(
    en: 'Paste cells',
    ar: 'لصق الخلايا',
    ur: 'سیلز پیسٹ کریں',
    hi: 'सेल पेस्ट करें',
  );
  static const addFirstRow = TranslatableString(
    en: 'Add First Row',
    ar: 'إضافة الصف الأول',
    ur: 'پہلی قطار شامل کریں',
    hi: 'पहली पंक्ति जोड़ें',
  );
  static const similarRow = TranslatableString(
    en: 'Similar row',
    ar: 'صف مماثل',
    ur: 'مشابہ قطار',
    hi: 'समान पंक्ति',
  );
  static const createRequestFromFolder = TranslatableString(
    en: 'Use entire folder for a material request',
    ar: 'استخدم المجلد بالكامل لطلب مواد',
    ur: 'پورا فولڈر میٹریل ریکویسٹ کے لیے استعمال کریں',
    hi: 'पूरे फ़ोल्डर से सामग्री अनुरोध बनाएँ',
  );
  static const sendWholeGroup = TranslatableString(
    en: 'Create request draft',
    ar: 'إنشاء مسودة طلب',
    ur: 'ریکویسٹ ڈرافٹ بنائیں',
    hi: 'अनुरोध ड्राफ्ट बनाएँ',
  );
  static const createRequestFromFolderDescription = TranslatableString(
    en: 'Copies every BOQ row into a private draft. Review it before submitting to Procurement.',
    ar: 'ينسخ كل صفوف جدول الكميات إلى مسودة خاصة. راجعها قبل إرسالها إلى المشتريات.',
    ur: 'ہر BOQ قطار کو نجی ڈرافٹ میں کاپی کرتا ہے۔ پروکیورمنٹ کو بھیجنے سے پہلے جائزہ لیں۔',
    hi: 'हर BOQ पंक्ति को निजी ड्राफ्ट में कॉपी करता है। प्रोक्योरमेंट को भेजने से पहले समीक्षा करें।',
  );
  static const noRequestReadyRows = TranslatableString(
    en: 'Add an item description or equipment tag to at least one row before creating a request draft.',
    ar: 'أضف وصف مادة أو وسم معدة إلى صف واحد على الأقل قبل إنشاء مسودة الطلب.',
    ur: 'ریکویسٹ ڈرافٹ بنانے سے پہلے کم از کم ایک قطار میں آئٹم کی تفصیل یا ایکوپمنٹ ٹیگ شامل کریں۔',
    hi: 'अनुरोध ड्राफ्ट बनाने से पहले कम से कम एक पंक्ति में आइटम विवरण या उपकरण टैग जोड़ें।',
  );
  static const save = TranslatableString(
    en: 'Save',
    ar: 'حفظ',
    ur: 'محفوظ کریں',
    hi: 'सहेजें',
  );
  static const saved = TranslatableString(
    en: 'Saved',
    ar: 'تم الحفظ',
    ur: 'محفوظ ہو گیا',
    hi: 'सहेजा गया',
  );
  static const saving = TranslatableString(
    en: 'Saving…',
    ar: 'جارٍ الحفظ…',
    ur: 'محفوظ ہو رہا ہے…',
    hi: 'सहेजा जा रहा है…',
  );
  static const unsavedChanges = TranslatableString(
    en: 'Unsaved changes',
    ar: 'تغييرات غير محفوظة',
    ur: 'غیر محفوظ تبدیلیاں',
    hi: 'असहेजे परिवर्तन',
  );
  static const syncConflict = TranslatableString(
    en: 'This worksheet changed elsewhere. Refresh to review the latest version.',
    ar: 'تغيرت ورقة العمل هذه في مكان آخر. حدّث لمراجعة أحدث إصدار.',
    ur: 'یہ ورک شیٹ کہیں اور تبدیل ہوئی ہے۔ تازہ ترین ورژن دیکھنے کے لیے ریفریش کریں۔',
    hi: 'यह वर्कशीट कहीं और बदल गई है। नवीनतम संस्करण देखने के लिए रीफ़्रेश करें।',
  );
  static const refresh = TranslatableString(
    en: 'Refresh',
    ar: 'تحديث',
    ur: 'ریفریش',
    hi: 'रीफ़्रेश',
  );
  static const readOnly = TranslatableString(
    en: 'Read only',
    ar: 'للقراءة فقط',
    ur: 'صرف پڑھنے کے لیے',
    hi: 'केवल पढ़ने के लिए',
  );
  static const readOnlyDescription = TranslatableString(
    en: 'Procurement can review the worksheet but cannot change its groups, columns or rows.',
    ar: 'يمكن للمشتريات مراجعة ورقة العمل ولكن لا يمكنها تغيير مجموعاتها أو أعمدتها أو صفوفها.',
    ur: 'پروکیورمنٹ ورک شیٹ کا جائزہ لے سکتا ہے مگر اس کے گروپ، کالم یا قطاریں تبدیل نہیں کر سکتا۔',
    hi: 'प्रोक्योरमेंट वर्कशीट की समीक्षा कर सकता है, पर उसके समूह, कॉलम या पंक्तियाँ नहीं बदल सकता।',
  );
  static const mobileEditor = TranslatableString(
    en: 'Edit row',
    ar: 'تعديل الصف',
    ur: 'قطار ایڈٹ کریں',
    hi: 'पंक्ति संपादित करें',
  );
  static const editMaterial = TranslatableString(
    en: 'Edit material',
    ar: 'تعديل المادة',
    ur: 'میٹریل ایڈٹ کریں',
    hi: 'सामग्री संपादित करें',
  );
  static const editorDescription = TranslatableString(
    en: 'Technical fields stay connected to this BOQ row and its linked requests.',
    ar: 'تبقى الحقول الفنية مرتبطة بصف جدول الكميات هذا وطلباته المرتبطة.',
    ur: 'تکنیکی فیلڈز اس BOQ قطار اور اس کی منسلک ریکوئسٹس سے جڑے رہتے ہیں۔',
    hi: 'तकनीकी फ़ील्ड इस BOQ पंक्ति और उससे जुड़े अनुरोधों से जुड़े रहते हैं।',
  );
  static const addMaterial = TranslatableString(
    en: 'Add Material',
    ar: 'إضافة مادة',
    ur: 'میٹریل شامل کریں',
    hi: 'सामग्री जोड़ें',
  );
  static const saveWorksheet = TranslatableString(
    en: 'Apply to worksheet',
    ar: 'تطبيق على ورقة العمل',
    ur: 'ورک شیٹ پر لاگو کریں',
    hi: 'वर्कशीट पर लागू करें',
  );
  static const unsavedWorksheetTitle = TranslatableString(
    en: 'Save worksheet changes?',
    ar: 'حفظ تغييرات ورقة العمل؟',
    ur: 'ورک شیٹ کی تبدیلیاں محفوظ کریں؟',
    hi: 'वर्कशीट बदलाव सहेजें?',
  );
  static const unsavedWorksheetBody = TranslatableString(
    en: 'Your edits are kept on this device for recovery. Save them to the project before leaving, or discard them explicitly.',
    ar: 'يتم الاحتفاظ بتعديلاتك على هذا الجهاز للاسترداد. احفظها في المشروع قبل المغادرة أو تجاهلها صراحةً.',
    ur: 'آپ کی ترامیم ریکوری کے لیے اس ڈیوائس پر رکھی گئی ہیں۔ جانے سے پہلے انہیں پراجیکٹ میں محفوظ کریں یا واضح طور پر ضائع کریں۔',
    hi: 'आपके संपादन रिकवरी के लिए इस डिवाइस पर रखे गए हैं। जाने से पहले उन्हें प्रोजेक्ट में सहेजें या स्पष्ट रूप से छोड़ें।',
  );
  static const saveAndContinue = TranslatableString(
    en: 'Save and continue',
    ar: 'حفظ ومتابعة',
    ur: 'محفوظ کریں اور جاری رکھیں',
    hi: 'सहेजें और जारी रखें',
  );
  static const outputUnsavedTitle = TranslatableString(
    en: 'Choose the BOQ output',
    ar: 'اختر مخرجات جدول الكميات',
    ur: 'BOQ آؤٹ پٹ منتخب کریں',
    hi: 'BOQ आउटपुट चुनें',
  );
  static const outputUnsavedBody = TranslatableString(
    en: 'This worksheet has uncommitted edits. Save first for a controlled revision, or generate a clearly marked DRAFT copy.',
    ar: 'تحتوي ورقة العمل على تعديلات غير معتمدة. احفظ أولاً لإصدار مضبوط أو أنشئ نسخة مسودة واضحة.',
    ur: 'اس ورک شیٹ میں غیر کمٹ شدہ ترامیم ہیں۔ کنٹرولڈ ریویژن کے لیے پہلے محفوظ کریں یا واضح DRAFT کاپی بنائیں۔',
    hi: 'इस वर्कशीट में असमर्थित संपादन हैं। नियंत्रित संशोधन के लिए पहले सहेजें या स्पष्ट DRAFT प्रति बनाएँ।',
  );
  static const draftCopy = TranslatableString(
    en: 'Generate DRAFT copy',
    ar: 'إنشاء نسخة مسودة',
    ur: 'DRAFT کاپی بنائیں',
    hi: 'DRAFT प्रति बनाएँ',
  );
  static const folderName = TranslatableString(
    en: 'Folder',
    ar: 'المجلد',
    ur: 'فولڈر',
    hi: 'फ़ोल्डर',
  );
  static const revision = TranslatableString(
    en: 'Revision',
    ar: 'المراجعة',
    ur: 'ریویژن',
    hi: 'संशोधन',
  );
  static const generated = TranslatableString(
    en: 'Generated',
    ar: 'تم الإنشاء',
    ur: 'تیار کردہ',
    hi: 'तैयार किया गया',
  );
  static const linkedWork = TranslatableString(
    en: 'Linked work',
    ar: 'العمل المرتبط',
    ur: 'منسلک کام',
    hi: 'जुड़ा कार्य',
  );
  static const lastEdited = TranslatableString(
    en: 'Last edited',
    ar: 'آخر تعديل',
    ur: 'آخری ترمیم',
    hi: 'अंतिम संपादन',
  );
  static const linkedRequests = TranslatableString(
    en: 'linked requests',
    ar: 'طلبات مرتبطة',
    ur: 'منسلک ریکویسٹس',
    hi: 'जुड़े अनुरोध',
  );
  static const linkedDocuments = TranslatableString(
    en: 'documents',
    ar: 'مستندات',
    ur: 'دستاویزات',
    hi: 'दस्तावेज़',
  );
  static const findInWorksheet = TranslatableString(
    en: 'Find in worksheet',
    ar: 'بحث في ورقة العمل',
    ur: 'ورک شیٹ میں تلاش کریں',
    hi: 'वर्कशीट में खोजें',
  );
  static const undo = TranslatableString(
    en: 'Undo',
    ar: 'تراجع',
    ur: 'واپس کریں',
    hi: 'पूर्ववत करें',
  );
  static const redo = TranslatableString(
    en: 'Redo',
    ar: 'إعادة',
    ur: 'دوبارہ کریں',
    hi: 'फिर करें',
  );
  static const clearFind = TranslatableString(
    en: 'Clear search',
    ar: 'مسح البحث',
    ur: 'تلاش صاف کریں',
    hi: 'खोज साफ़ करें',
  );
  static const possibleDuplicate = TranslatableString(
    en: 'Possible duplicate',
    ar: 'تكرار محتمل',
    ur: 'ممکنہ ڈپلیکیٹ',
    hi: 'संभावित डुप्लिकेट',
  );
  static const mappingOptional = TranslatableString(
    en: 'Material Request mapping (optional)',
    ar: 'تعيين طلب المواد (اختياري)',
    ur: 'میٹریل ریکویسٹ میپنگ (اختیاری)',
    hi: 'सामग्री अनुरोध मैपिंग (वैकल्पिक)',
  );
  static const duplicateColumnHeading = TranslatableString(
    en: 'A column with this heading already exists.',
    ar: 'يوجد عمود بهذا العنوان بالفعل.',
    ur: 'اس ہیڈنگ والا کالم پہلے سے موجود ہے۔',
    hi: 'इस शीर्षक वाला कॉलम पहले से मौजूद है।',
  );
  static const mappingAlreadyUsed = TranslatableString(
    en: 'This Material Request mapping is already used by another column.',
    ar: 'يُستخدم تعيين طلب المواد هذا بالفعل بواسطة عمود آخر.',
    ur: 'یہ میٹریل ریکویسٹ میپنگ پہلے ہی دوسرے کالم میں استعمال ہو رہی ہے۔',
    hi: 'यह सामग्री अनुरोध मैपिंग पहले से दूसरे कॉलम में उपयोग हो रही है।',
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
  static const deleteColumn = TranslatableString(
    en: 'Delete column',
    ar: 'حذف العمود',
    ur: 'کالم حذف کریں',
    hi: 'कॉलम हटाएँ',
  );
  static const deleteColumnConfirmation = TranslatableString(
    en: 'Delete this populated column? Its legacy values stay in the audited worksheet history.',
    ar: 'هل تريد حذف هذا العمود المعبأ؟ تبقى قيمه السابقة في سجل ورقة العمل المدقق.',
    ur: 'کیا اس بھرے ہوئے کالم کو حذف کریں؟ اس کی پرانی ویلیوز آڈٹ شدہ ورک شیٹ ہسٹری میں رہیں گی۔',
    hi: 'क्या इस भरे कॉलम को हटाना है? इसके पुराने मान ऑडिटेड वर्कशीट इतिहास में रहेंगे।',
  );
  static const archiveGroup = TranslatableString(
    en: 'Hide folder in this scope',
    ar: 'إخفاء المجلد في هذا النطاق',
    ur: 'اس اسکوپ میں فولڈر چھپائیں',
    hi: 'इस स्कोप में फ़ोल्डर छिपाएँ',
  );
  static const archived = TranslatableString(
    en: 'Archived',
    ar: 'مؤرشف',
    ur: 'آرکائیو شدہ',
    hi: 'आर्काइव किया गया',
  );
  static const deleteRow = TranslatableString(
    en: 'Delete row',
    ar: 'حذف الصف',
    ur: 'قطار حذف کریں',
    hi: 'पंक्ति हटाएँ',
  );
  static const deleteRowConfirmation = TranslatableString(
    en: 'Delete this populated row? Its values remain in the audited worksheet history.',
    ar: 'هل تريد حذف هذا الصف المعبأ؟ تبقى قيمه في سجل ورقة العمل المدقق.',
    ur: 'کیا اس بھرے ہوئے قطار کو حذف کریں؟ اس کی ویلیوز آڈٹ شدہ ورک شیٹ ہسٹری میں رہیں گی۔',
    hi: 'क्या इस भरी हुई पंक्ति को हटाना है? इसके मान ऑडिटेड वर्कशीट इतिहास में रहेंगे।',
  );
  static const noRows = TranslatableString(
    en: 'No rows yet. Add a column, then start the worksheet with a blank row.',
    ar: 'لا توجد صفوف بعد. أضف عموداً ثم ابدأ ورقة العمل بصف فارغ.',
    ur: 'ابھی کوئی قطار نہیں۔ کالم شامل کریں، پھر خالی قطار سے ورک شیٹ شروع کریں۔',
    hi: 'अभी कोई पंक्तियाँ नहीं हैं। कॉलम जोड़ें, फिर खाली पंक्ति से वर्कशीट शुरू करें।',
  );
  static const noColumns = TranslatableString(
    en: 'No columns yet. Add a column before entering a row.',
    ar: 'لا توجد أعمدة بعد. أضف عموداً قبل إدخال صف.',
    ur: 'ابھی کوئی کالم نہیں۔ قطار درج کرنے سے پہلے کالم شامل کریں۔',
    hi: 'अभी कोई कॉलम नहीं हैं। पंक्ति दर्ज करने से पहले एक कॉलम जोड़ें।',
  );
  static const add = TranslatableString(
    en: 'Add',
    ar: 'إضافة',
    ur: 'شامل کریں',
    hi: 'जोड़ें',
  );
  static const cancel = TranslatableString(
    en: 'Cancel',
    ar: 'إلغاء',
    ur: 'منسوخ کریں',
    hi: 'रद्द करें',
  );
  static const archiveGroupConfirmation = TranslatableString(
    en: 'Archive this folder only in the current Common/building scope? Its worksheet, documents and request links stay in audit history and can be restored.',
    ar: 'أرشفة هذا المجلد في النطاق المشترك/المبنى الحالي فقط؟ ستبقى ورقة العمل والمستندات وروابط الطلبات في سجل التدقيق ويمكن استعادتها.',
    ur: 'کیا یہ فولڈر صرف موجودہ کامن/بلڈنگ اسکوپ میں آرکائیو کریں؟ اس کی ورک شیٹ، دستاویزات اور ریکویسٹ لنکس آڈٹ ہسٹری میں رہیں گے اور اسے بحال کیا جا سکے گا۔',
    hi: 'क्या इस फ़ोल्डर को केवल वर्तमान कॉमन/बिल्डिंग स्कोप में आर्काइव करना है? इसकी वर्कशीट, दस्तावेज़ और अनुरोध लिंक ऑडिट इतिहास में रहेंगे और इसे पुनर्स्थापित किया जा सकेगा।',
  );
  static const saveFailed = TranslatableString(
    en: 'Could not save this worksheet. Check the highlighted details and try again.',
    ar: 'تعذر حفظ ورقة العمل. تحقق من التفاصيل المميزة وحاول مرة أخرى.',
    ur: 'ورک شیٹ محفوظ نہیں ہو سکی۔ نمایاں تفصیلات چیک کریں اور دوبارہ کوشش کریں۔',
    hi: 'वर्कशीट सहेजी नहीं जा सकी। हाइलाइट किए गए विवरण जाँचें और फिर प्रयास करें।',
  );
  static const offlineSave = TranslatableString(
    en: 'You are offline. Your worksheet is kept on this device; reconnect before applying it.',
    ar: 'أنت غير متصل. تم الاحتفاظ بورقة العمل على هذا الجهاز؛ أعد الاتصال قبل تطبيقها.',
    ur: 'آپ آف لائن ہیں۔ ورک شیٹ اس ڈیوائس پر محفوظ ہے؛ اطلاق سے پہلے دوبارہ کنیکٹ کریں۔',
    hi: 'आप ऑफ़लाइन हैं। वर्कशीट इस डिवाइस पर सुरक्षित है; इसे लागू करने से पहले फिर कनेक्ट करें।',
  );
  static const permissionDenied = TranslatableString(
    en: 'Your role cannot change this worksheet or its protected commercial fields.',
    ar: 'لا يسمح دورك بتغيير ورقة العمل هذه أو حقولها التجارية المحمية.',
    ur: 'آپ کا کردار اس ورک شیٹ یا اس کے محفوظ کمرشل فیلڈز کو تبدیل نہیں کر سکتا۔',
    hi: 'आपकी भूमिका इस वर्कशीट या इसके सुरक्षित वाणिज्यिक फ़ील्ड नहीं बदल सकती।',
  );
  static const serviceUnavailable = TranslatableString(
    en: 'The BOQ service is temporarily unavailable. Your local worksheet has not been discarded.',
    ar: 'خدمة جدول الكميات غير متاحة مؤقتاً. لم يتم حذف ورقة العمل المحلية.',
    ur: 'بی او کیو سروس عارضی طور پر دستیاب نہیں۔ آپ کی مقامی ورک شیٹ ضائع نہیں ہوئی۔',
    hi: 'BOQ सेवा अस्थायी रूप से उपलब्ध नहीं है। आपकी स्थानीय वर्कशीट हटाई नहीं गई है।',
  );
  static const description = TranslatableString(
    en: 'Item description',
    ar: 'وصف الصنف',
    ur: 'آئٹم کی تفصیل',
    hi: 'आइटम विवरण',
  );
  static const size = TranslatableString(
    en: 'Size / dimension',
    ar: 'المقاس / الأبعاد',
    ur: 'سائز / ڈائمینشن',
    hi: 'आकार / आयाम',
  );
  static const model = TranslatableString(
    en: 'Model',
    ar: 'الطراز',
    ur: 'ماڈل',
    hi: 'मॉडल',
  );
  static const equipmentTag = TranslatableString(
    en: 'Equipment tag',
    ar: 'وسم المعدة',
    ur: 'آلاتی ٹیگ',
    hi: 'उपकरण टैग',
  );
  static const brandOrigin = TranslatableString(
    en: 'Brand / origin',
    ar: 'العلامة التجارية / المنشأ',
    ur: 'برانڈ / اصل',
    hi: 'ब्रांड / मूल',
  );
  static const quantity = TranslatableString(
    en: 'Quantity',
    ar: 'الكمية',
    ur: 'مقدار',
    hi: 'मात्रा',
  );
  static const unit = TranslatableString(
    en: 'Unit',
    ar: 'الوحدة',
    ur: 'یونٹ',
    hi: 'इकाई',
  );
  static const planningModelTag = TranslatableString(
    en: 'Planning model / tag',
    ar: 'نموذج / علامة التخطيط',
    ur: 'پلاننگ ماڈل / ٹیگ',
    hi: 'प्लानिंग मॉडल / टैग',
  );
  static const importWorkbook = TranslatableString(
    en: 'Import Excel',
    ar: 'استيراد Excel',
    ur: 'Excel امپورٹ کریں',
    hi: 'Excel आयात करें',
  );
  static const exportWorkbook = TranslatableString(
    en: 'Export Excel',
    ar: 'تصدير مصنف',
    ur: 'ورک بک ایکسپورٹ کریں',
    hi: 'वर्कबुक निर्यात करें',
  );
  static const chooseWorkbook = TranslatableString(
    en: 'Choose XLSX file',
    ar: 'اختر ملف XLSX',
    ur: 'XLSX فائل منتخب کریں',
    hi: 'XLSX फ़ाइल चुनें',
  );
  static const excelImport = TranslatableString(
    en: 'Excel import',
    ar: 'استيراد Excel',
    ur: 'Excel امپورٹ',
    hi: 'Excel आयात',
  );
  static const importFileStep = TranslatableString(
    en: 'File',
    ar: 'الملف',
    ur: 'فائل',
    hi: 'फ़ाइल',
  );
  static const importSheetStep = TranslatableString(
    en: 'Sheet',
    ar: 'الورقة',
    ur: 'شیٹ',
    hi: 'शीट',
  );
  static const importMapStep = TranslatableString(
    en: 'Map',
    ar: 'التعيين',
    ur: 'میپ',
    hi: 'मैप',
  );
  static const importReviewStep = TranslatableString(
    en: 'Review',
    ar: 'المراجعة',
    ur: 'جائزہ',
    hi: 'समीक्षा',
  );
  static const chooseWorkbookTitle = TranslatableString(
    en: 'Choose a workbook',
    ar: 'اختر مصنفاً',
    ur: 'ورک بک منتخب کریں',
    hi: 'वर्कबुक चुनें',
  );
  static const chooseWorkbookDescription = TranslatableString(
    en: 'The file is processed as a preview. Nothing changes before confirmation.',
    ar: 'تتم معالجة الملف كمعاينة. لا يتغير شيء قبل التأكيد.',
    ur: 'فائل کو پری ویو کے طور پر پروسیس کیا جاتا ہے۔ تصدیق سے پہلے کچھ تبدیل نہیں ہوتا۔',
    hi: 'फ़ाइल को पूर्वावलोकन के रूप में संसाधित किया जाता है। पुष्टि से पहले कुछ नहीं बदलता।',
  );
  static const uploadEquipmentSchedule = TranslatableString(
    en: 'Upload equipment schedule',
    ar: 'رفع جدول المعدات',
    ur: 'آلات کا شیڈول اپ لوڈ کریں',
    hi: 'उपकरण शेड्यूल अपलोड करें',
  );
  static const xlsxConfiguredLimit = TranslatableString(
    en: '.xlsx files · up to the configured limit',
    ar: 'ملفات .xlsx · حتى الحد المضبوط',
    ur: '.xlsx فائلیں · مقررہ حد تک',
    hi: '.xlsx फ़ाइलें · कॉन्फ़िगर की गई सीमा तक',
  );
  static const chooseFile = TranslatableString(
    en: 'Choose File',
    ar: 'اختر الملف',
    ur: 'فائل منتخب کریں',
    hi: 'फ़ाइल चुनें',
  );
  static const continueAction = TranslatableString(
    en: 'Continue',
    ar: 'متابعة',
    ur: 'جاری رکھیں',
    hi: 'जारी रखें',
  );
  static const importDestination = TranslatableString(
    en: 'Import destination',
    ar: 'وجهة الاستيراد',
    ur: 'امپورٹ کی منزل',
    hi: 'आयात गंतव्य',
  );
  static const importDestinationDescription = TranslatableString(
    en: '{scope} → {folder}. Imported rows remain inside this scope and folder.',
    ar: '{scope} ← {folder}. تبقى الصفوف المستوردة داخل هذا النطاق والمجلد.',
    ur: '{scope} → {folder}۔ امپورٹ شدہ قطاریں اسی اسکوپ اور فولڈر میں رہتی ہیں۔',
    hi: '{scope} → {folder}। आयातित पंक्तियाँ इसी स्कोप और फ़ोल्डर में रहती हैं।',
  );
  static const chooseSheetTitle = TranslatableString(
    en: 'Choose a worksheet',
    ar: 'اختر ورقة عمل',
    ur: 'ورک شیٹ منتخب کریں',
    hi: 'वर्कशीट चुनें',
  );
  static const chooseSheetDescription = TranslatableString(
    en: 'Confirm the source sheet, title and header row before mapping columns.',
    ar: 'أكد ورقة المصدر والعنوان وصف العناوين قبل تعيين الأعمدة.',
    ur: 'کالم میپ کرنے سے پہلے سورس شیٹ، عنوان اور ہیڈر قطار کی تصدیق کریں۔',
    hi: 'कॉलम मैप करने से पहले स्रोत शीट, शीर्षक और हेडर पंक्ति की पुष्टि करें।',
  );
  static const mapColumnsTitle = TranslatableString(
    en: 'Map columns',
    ar: 'تعيين الأعمدة',
    ur: 'کالم میپ کریں',
    hi: 'कॉलम मैप करें',
  );
  static const mapColumnsDescription = TranslatableString(
    en: 'Confirm how workbook headings become Yorks material fields.',
    ar: 'أكد كيفية تحويل عناوين المصنف إلى حقول مواد يوركس.',
    ur: 'تصدیق کریں کہ ورک بک ہیڈنگز یورکس میٹریل فیلڈز کیسے بنتی ہیں۔',
    hi: 'पुष्टि करें कि वर्कबुक शीर्षक Yorks सामग्री फ़ील्ड कैसे बनते हैं।',
  );
  static const mapped = TranslatableString(
    en: 'Mapped',
    ar: 'مُعيّن',
    ur: 'میپ شدہ',
    hi: 'मैप किया गया',
  );
  static const retainedColumn = TranslatableString(
    en: 'Retained',
    ar: 'محفوظ',
    ur: 'محفوظ',
    hi: 'सुरक्षित',
  );
  static const otherColumnsStayAvailable = TranslatableString(
    en: 'Other columns stay available',
    ar: 'تبقى الأعمدة الأخرى متاحة',
    ur: 'دوسرے کالم دستیاب رہتے ہیں',
    hi: 'अन्य कॉलम उपलब्ध रहते हैं',
  );
  static const otherColumnsStayAvailableDescription = TranslatableString(
    en: 'Unmapped technical columns remain editable in the BOQ and are never silently discarded.',
    ar: 'تبقى الأعمدة الفنية غير المعيّنة قابلة للتعديل في جدول الكميات ولا يتم تجاهلها بصمت أبداً.',
    ur: 'غیر میپ شدہ تکنیکی کالم BOQ میں قابل تدوین رہتے ہیں اور کبھی خاموشی سے ضائع نہیں ہوتے۔',
    hi: 'बिना मैप किए तकनीकी कॉलम BOQ में संपादन योग्य रहते हैं और कभी चुपचाप हटाए नहीं जाते।',
  );
  static const reviewWorkbook = TranslatableString(
    en: 'Review workbook',
    ar: 'مراجعة المصنف',
    ur: 'ورک بک کا جائزہ لیں',
    hi: 'वर्कबुक की समीक्षा करें',
  );
  static const readyToImport = TranslatableString(
    en: 'Ready to import',
    ar: 'جاهز للاستيراد',
    ur: 'امپورٹ کے لیے تیار',
    hi: 'आयात के लिए तैयार',
  );
  static const rowsFound = TranslatableString(
    en: 'Rows found',
    ar: 'الصفوف الموجودة',
    ur: 'ملنے والی قطاریں',
    hi: 'मिली पंक्तियाँ',
  );
  static const warnings = TranslatableString(
    en: 'Warnings',
    ar: 'تحذيرات',
    ur: 'انتباہات',
    hi: 'चेतावनियाँ',
  );
  static const fatalErrors = TranslatableString(
    en: 'Fatal errors',
    ar: 'أخطاء مانعة',
    ur: 'سنگین غلطیاں',
    hi: 'गंभीर त्रुटियाँ',
  );
  static const sheetTitle = TranslatableString(
    en: 'Sheet title',
    ar: 'عنوان الورقة',
    ur: 'شیٹ کا عنوان',
    hi: 'शीट शीर्षक',
  );
  static const mappingReadyDescription = TranslatableString(
    en: '{mapped} of {total} recognized · no source column will be dropped',
    ar: 'تم التعرف على {mapped} من {total} · لن يتم إسقاط أي عمود مصدر',
    ur: '{total} میں سے {mapped} شناخت شدہ · کوئی سورس کالم ضائع نہیں ہوگا',
    hi: '{total} में से {mapped} पहचाने गए · कोई स्रोत कॉलम नहीं हटेगा',
  );
  static const importMaterials = TranslatableString(
    en: 'Import {count} Materials',
    ar: 'استيراد {count} مادة',
    ur: '{count} میٹریلز امپورٹ کریں',
    hi: '{count} सामग्री आयात करें',
  );
  static const previewRetainedAfterFailure = TranslatableString(
    en: 'The import was not committed. Your preview is still here so you can review it or try again.',
    ar: 'لم يتم اعتماد الاستيراد. لا تزال المعاينة موجودة لتراجعها أو تحاول مرة أخرى.',
    ur: 'امپورٹ کمٹ نہیں ہوا۔ آپ کا پری ویو یہاں موجود ہے تاکہ آپ جائزہ لے سکیں یا دوبارہ کوشش کریں۔',
    hi: 'आयात कमिट नहीं हुआ। आपका पूर्वावलोकन यहीं है ताकि आप समीक्षा या पुनः प्रयास कर सकें।',
  );
  static const commercialImportPermissionRequired = TranslatableString(
    en: 'This workbook contains recognized commercial cost columns. Remove them from the source file or ask an authorized commercial user to import it.',
    ar: 'يحتوي هذا المصنف على أعمدة تكلفة تجارية معروفة. أزلها من الملف المصدر أو اطلب من مستخدم تجاري مخول استيراده.',
    ur: 'اس ورک بک میں تسلیم شدہ تجارتی لاگت کے کالم ہیں۔ انہیں ماخذ فائل سے ہٹائیں یا کسی مجاز تجارتی صارف سے امپورٹ کروائیں۔',
    hi: 'इस वर्कबुक में पहचाने गए वाणिज्यिक लागत कॉलम हैं। उन्हें स्रोत फ़ाइल से हटाएँ या किसी अधिकृत वाणिज्यिक उपयोगकर्ता से आयात कराएँ।',
  );
  static const importConflictTitle = TranslatableString(
    en: 'Worksheet changed',
    ar: 'تغيرت ورقة العمل',
    ur: 'ورک شیٹ تبدیل ہو گئی',
    hi: 'वर्कशीट बदल गई',
  );
  static const importConflictBody = TranslatableString(
    en: 'This preview was based on an older worksheet version. Refresh the worksheet, then review the import again before committing it.',
    ar: 'استندت هذه المعاينة إلى إصدار أقدم من ورقة العمل. حدّث ورقة العمل ثم راجع الاستيراد مرة أخرى قبل اعتماده.',
    ur: 'یہ پری ویو ورک شیٹ کے پرانے ورژن پر مبنی تھا۔ ورک شیٹ ریفریش کریں، پھر امپورٹ کمٹ کرنے سے پہلے دوبارہ جائزہ لیں۔',
    hi: 'यह पूर्वावलोकन वर्कशीट के पुराने संस्करण पर आधारित था। वर्कशीट रीफ़्रेश करें, फिर आयात कमिट करने से पहले दोबारा समीक्षा करें।',
  );
  static const workbookReadFailed = TranslatableString(
    en: 'The workbook could not be read. Choose a valid configured Excel file and try again.',
    ar: 'تعذرت قراءة المصنف. اختر ملف Excel صالحاً ومهيأً ثم حاول مرة أخرى.',
    ur: 'ورک بک پڑھی نہیں جا سکی۔ درست ترتیب شدہ Excel فائل منتخب کریں اور دوبارہ کوشش کریں۔',
    hi: 'वर्कबुक पढ़ी नहीं जा सकी। मान्य कॉन्फ़िगर की गई Excel फ़ाइल चुनकर फिर प्रयास करें।',
  );
  static const discardRowChanges = TranslatableString(
    en: 'Discard row changes?',
    ar: 'تجاهل تغييرات الصف؟',
    ur: 'قطار کی تبدیلیاں ضائع کریں؟',
    hi: 'पंक्ति के बदलाव छोड़ें?',
  );
  static const discardRowChangesBody = TranslatableString(
    en: 'The unsaved edits in this material row will be removed.',
    ar: 'ستتم إزالة التعديلات غير المحفوظة في صف المادة هذا.',
    ur: 'اس میٹریل کی قطار میں غیر محفوظ ترامیم ختم ہو جائیں گی۔',
    hi: 'इस सामग्री पंक्ति के सहेजे नहीं गए बदलाव हट जाएंगे।',
  );
  static const importPreview = TranslatableString(
    en: 'Import preview',
    ar: 'معاينة الاستيراد',
    ur: 'امپورٹ پری ویو',
    hi: 'आयात पूर्वावलोकन',
  );
  static const worksheetSelection = TranslatableString(
    en: 'Worksheet',
    ar: 'ورقة العمل',
    ur: 'ورک شیٹ',
    hi: 'वर्कशीट',
  );
  static const headerRow = TranslatableString(
    en: 'Header row',
    ar: 'صف العنوان',
    ur: 'ہیڈر قطار',
    hi: 'हेडर पंक्ति',
  );
  static const detectedTitle = TranslatableString(
    en: 'Worksheet title',
    ar: 'عنوان ورقة العمل',
    ur: 'ورک شیٹ کا عنوان',
    hi: 'वर्कशीट शीर्षक',
  );
  static const columnMapping = TranslatableString(
    en: 'Column mapping',
    ar: 'تعيين الأعمدة',
    ur: 'کالم میپنگ',
    hi: 'कॉलम मैपिंग',
  );
  static const noCanonicalMapping = TranslatableString(
    en: 'Keep as worksheet-only column',
    ar: 'الاحتفاظ به كعمود لورقة العمل فقط',
    ur: 'صرف ورک شیٹ کالم کے طور پر رکھیں',
    hi: 'केवल वर्कशीट कॉलम के रूप में रखें',
  );
  static const previewRows = TranslatableString(
    en: 'Preview rows',
    ar: 'معاينة الصفوف',
    ur: 'پری ویو قطاریں',
    hi: 'पूर्वावलोकन पंक्तियाँ',
  );
  static const commitImport = TranslatableString(
    en: 'Import into this worksheet',
    ar: 'استيراد إلى ورقة العمل هذه',
    ur: 'اس ورک شیٹ میں امپورٹ کریں',
    hi: 'इस वर्कशीट में आयात करें',
  );
  static const importDescription = TranslatableString(
    en: 'Review the detected title, header row and mappings before replacing this worksheet. Importing never submits a Material Request.',
    ar: 'راجع العنوان وصف العناوين والتعيينات قبل استبدال ورقة العمل هذه. الاستيراد لا يرسل طلب مواد أبداً.',
    ur: 'اس ورک شیٹ کو تبدیل کرنے سے پہلے شناخت شدہ عنوان، ہیڈر قطار اور میپنگز دیکھیں۔ امپورٹ کبھی میٹریل ریکوئسٹ جمع نہیں کرتا۔',
    hi: 'इस वर्कशीट को बदलने से पहले पहचाने गए शीर्षक, हेडर पंक्ति और मैपिंग की समीक्षा करें। आयात कभी सामग्री अनुरोध जमा नहीं करता।',
  );
  static const imported = TranslatableString(
    en: 'Workbook imported.',
    ar: 'تم استيراد المصنف.',
    ur: 'ورک بک امپورٹ ہو گئی۔',
    hi: 'वर्कबुक आयात हो गई।',
  );
  static const exported = TranslatableString(
    en: 'Workbook export is ready.',
    ar: 'تصدير المصنف جاهز.',
    ur: 'ورک بک ایکسپورٹ تیار ہے۔',
    hi: 'वर्कबुक निर्यात तैयार है।',
  );
  static const importFailed = TranslatableString(
    en: 'Could not import this workbook. Check the file and preview details, then try again.',
    ar: 'تعذر استيراد هذا المصنف. تحقق من الملف وتفاصيل المعاينة ثم حاول مرة أخرى.',
    ur: 'یہ ورک بک امپورٹ نہیں ہو سکی۔ فائل اور پری ویو تفصیلات دیکھیں، پھر دوبارہ کوشش کریں۔',
    hi: 'यह कार्यपुस्तिका आयात नहीं हो सकी। फ़ाइल और पूर्वावलोकन विवरण जाँचें, फिर प्रयास करें।',
  );
  static const exportFailed = TranslatableString(
    en: 'Could not export this worksheet.',
    ar: 'تعذر تصدير ورقة العمل هذه.',
    ur: 'یہ ورک شیٹ ایکسپورٹ نہیں ہو سکی۔',
    hi: 'यह वर्कशीट निर्यात नहीं हो सकी।',
  );
  static const importNoColumns = TranslatableString(
    en: 'Choose a header row that contains at least one column heading.',
    ar: 'اختر صف عنوان يحتوي على عنوان عمود واحد على الأقل.',
    ur: 'ایسی ہیڈر قطار منتخب کریں جس میں کم از کم ایک کالم ہیڈنگ ہو۔',
    hi: 'ऐसी हेडर पंक्ति चुनें जिसमें कम से कम एक कॉलम शीर्षक हो।',
  );
  static const importBlankHeading = TranslatableString(
    en: 'Give every imported column a heading before continuing.',
    ar: 'أعطِ كل عمود مستورد عنواناً قبل المتابعة.',
    ur: 'جاری رکھنے سے پہلے ہر امپورٹ شدہ کالم کو ہیڈنگ دیں۔',
    hi: 'आगे बढ़ने से पहले हर आयातित कॉलम को शीर्षक दें।',
  );
  static const importDuplicateHeading = TranslatableString(
    en: 'Imported column headings must be unique.',
    ar: 'يجب أن تكون عناوين الأعمدة المستوردة فريدة.',
    ur: 'امپورٹ شدہ کالم ہیڈنگز منفرد ہونی چاہئیں۔',
    hi: 'आयातित कॉलम शीर्षक अद्वितीय होने चाहिए।',
  );
  static const importDuplicateCanonical = TranslatableString(
    en: 'Use each searchable mapping only once.',
    ar: 'استخدم كل تعيين قابل للبحث مرة واحدة فقط.',
    ur: 'ہر قابل تلاش میپنگ صرف ایک بار استعمال کریں۔',
    hi: 'प्रत्येक खोज योग्य मैपिंग केवल एक बार उपयोग करें।',
  );
}
