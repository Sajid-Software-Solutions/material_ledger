import 'app_strings.dart';

/// Phone-specific copy; shared project terms retain their existing translations.
abstract final class YorksV1ProjectSetupMobileStrings {
  static const materialsLater = TranslatableString(
    en: 'Material lines are not required during project creation. You can add them after the project has been created.',
    ar: 'بنود المواد غير مطلوبة أثناء إنشاء المشروع. يمكنك إضافتها بعد إنشاء المشروع.',
    ur: 'پراجیکٹ بنانے کے دوران مواد کی لائنیں ضروری نہیں۔ پراجیکٹ بننے کے بعد انہیں شامل کر سکتے ہیں۔',
    hi: 'परियोजना बनाते समय सामग्री पंक्तियाँ आवश्यक नहीं हैं। परियोजना बनने के बाद उन्हें जोड़ सकते हैं।',
  );
  static const availablePeople = TranslatableString(
    en: 'Available people',
    ar: 'الأشخاص المتاحون',
    ur: 'دستیاب افراد',
    hi: 'उपलब्ध लोग',
  );
  static const selectedTeam = TranslatableString(
    en: 'Selected team ({count})',
    ar: 'الفريق المحدد ({count})',
    ur: 'منتخب ٹیم ({count})',
    hi: 'चुनी गई टीम ({count})',
  );
  static const commonScopeHelp = TranslatableString(
    en: 'Common is a shared scope added automatically. You cannot edit or delete it during setup.',
    ar: 'النطاق المشترك يُضاف تلقائياً. لا يمكنك تعديله أو حذفه أثناء الإعداد.',
    ur: 'مشترکہ دائرہ خود شامل ہوتا ہے۔ سیٹ اپ میں اسے تبدیل یا حذف نہیں کیا جا سکتا۔',
    hi: 'साझा क्षेत्र अपने आप जुड़ता है। सेटअप के दौरान इसे बदल या हटा नहीं सकते।',
  );
  static const frpRoomHelp = TranslatableString(
    en: 'Select if this building has an FRP room.',
    ar: 'حدد إذا كان المبنى يحتوي على غرفة FRP.',
    ur: 'اگر اس عمارت میں FRP کمرہ ہے تو منتخب کریں۔',
    hi: 'यदि इस इमारत में FRP कमरा है तो चुनें।',
  );
}
