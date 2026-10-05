import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';

enum YorksV1ProjectSetupCompletionText {
  createdTitle,
  updatedTitle,
  activeDescription,
  updatedDescription,
  draftDescription,
  activationPending,
  filesPending,
  recoveryPending,
  summaryTitle,
  summaryDescription,
  nextActionsTitle,
  nextActionsDescription,
  nextStepsTitle,
  nextStepsDescription,
  editProject,
  openProject,
  addBoq,
  inviteTeam,
  uploadDocuments,
  returnToProjects,
  editLaterHint,
  referenceLabel,
  nameLabel,
  activeState,
  draftState,
  onHoldState,
  completedState,
  archivedState,
  dismissBanner,
  addBoqStepTitle,
  addBoqDescription,
  createRequests,
  createRequestsDescription,
  uploadDocumentsStepTitle,
  uploadDocumentsDescription,
  inviteTeamStepTitle,
  inviteTeamDescription,
}

/// Localized copy is supplied independently of confirmed data and callbacks.
class YorksV1ProjectSetupCompletionCopy {
  YorksV1ProjectSetupCompletionCopy({
    required this.language,
    required Map<YorksV1ProjectSetupCompletionText, String> labels,
  }) : _labels = Map.unmodifiable(labels) {
    if (!YorksV1ProjectSetupCompletionText.values.every(_labels.containsKey)) {
      throw ArgumentError('Incomplete project completion copy');
    }
  }

  factory YorksV1ProjectSetupCompletionCopy.localized(AppLanguage language) =>
      YorksV1ProjectSetupCompletionCopy(
        language: language,
        labels: {
          for (final entry
              in YorksV1ProjectSetupCompletionStrings.labels.entries)
            entry.key: entry.value.active(language),
        },
      );

  final AppLanguage language;
  final Map<YorksV1ProjectSetupCompletionText, String> _labels;

  String operator [](YorksV1ProjectSetupCompletionText key) => _labels[key]!;
}

abstract final class YorksV1ProjectSetupCompletionStrings {
  static const labels = <YorksV1ProjectSetupCompletionText, TranslatableString>{
    YorksV1ProjectSetupCompletionText.createdTitle: TranslatableString(
      en: 'Project created',
      ar: 'تم إنشاء المشروع',
      ur: 'پراجیکٹ بن گیا',
      hi: 'प्रोजेक्ट बनाया गया',
    ),
    YorksV1ProjectSetupCompletionText.updatedTitle: TranslatableString(
      en: 'Project updated',
      ar: 'تم تحديث المشروع',
      ur: 'پراجیکٹ اپ ڈیٹ ہو گیا',
      hi: 'प्रोजेक्ट अपडेट किया गया',
    ),
    YorksV1ProjectSetupCompletionText.activeDescription: TranslatableString(
      en: 'Your project workspace is ready for the next steps available to your team.',
      ar: 'مساحة عمل المشروع جاهزة للخطوات التالية المتاحة لفريقك.',
      ur: 'پراجیکٹ ورک اسپیس آپ کی ٹیم کے لیے دستیاب اگلے مراحل کے لیے تیار ہے۔',
      hi: 'आपका प्रोजेक्ट कार्यक्षेत्र आपकी टीम के लिए उपलब्ध अगले चरणों के लिए तैयार है।',
    ),
    YorksV1ProjectSetupCompletionText.updatedDescription: TranslatableString(
      en: 'Your project changes have been saved.',
      ar: 'تم حفظ تغييرات المشروع.',
      ur: 'پراجیکٹ کی تبدیلیاں محفوظ ہو گئی ہیں۔',
      hi: 'आपके प्रोजेक्ट के परिवर्तन सहेजे गए हैं।',
    ),
    YorksV1ProjectSetupCompletionText.draftDescription: TranslatableString(
      en: 'Your project is saved as Draft. Open the project workspace to resolve activation.',
      ar: 'تم حفظ المشروع كمسودة. افتح مساحة عمل المشروع لاستكمال التفعيل.',
      ur: 'پراجیکٹ ڈرافٹ کے طور پر محفوظ ہے۔ ایکٹیویشن مکمل کرنے کے لیے پراجیکٹ ورک اسپیس کھولیں۔',
      hi: 'आपका प्रोजेक्ट ड्राफ़्ट के रूप में सहेजा गया है। सक्रियण पूरा करने के लिए प्रोजेक्ट कार्यक्षेत्र खोलें।',
    ),
    YorksV1ProjectSetupCompletionText.activationPending: TranslatableString(
      en: 'Activation has not been confirmed. Check its status before changing the project or team.',
      ar: 'لم يتم تأكيد التفعيل. تحقق من حالته قبل تغيير المشروع أو الفريق.',
      ur: 'ایکٹیویشن کی تصدیق نہیں ہوئی۔ پراجیکٹ یا ٹیم بدلنے سے پہلے اس کا اسٹیٹس چیک کریں۔',
      hi: 'सक्रियण की पुष्टि नहीं हुई है। प्रोजेक्ट या टीम बदलने से पहले उसकी स्थिति जाँचें।',
    ),
    YorksV1ProjectSetupCompletionText.filesPending: TranslatableString(
      en: 'Some selected files still need attention. Your project is saved.',
      ar: 'بعض الملفات المحددة ما زالت بحاجة إلى متابعة. تم حفظ المشروع.',
      ur: 'کچھ منتخب فائلوں پر ابھی توجہ درکار ہے۔ پراجیکٹ محفوظ ہے۔',
      hi: 'कुछ चुनी गई फ़ाइलों पर अभी ध्यान देना है। आपका प्रोजेक्ट सहेजा गया है।',
    ),
    YorksV1ProjectSetupCompletionText.recoveryPending: TranslatableString(
      en: 'The project is saved. Local recovery still needs attention; keep the original operation available.',
      ar: 'تم حفظ المشروع. الاسترداد المحلي ما زال بحاجة إلى متابعة؛ احتفظ بالعملية الأصلية متاحة.',
      ur: 'پراجیکٹ محفوظ ہے۔ مقامی ریکوری پر ابھی توجہ درکار ہے؛ اصل کارروائی دستیاب رکھیں۔',
      hi: 'प्रोजेक्ट सहेजा गया है। स्थानीय पुनर्प्राप्ति पर अभी ध्यान देना है; मूल कार्रवाई उपलब्ध रखें।',
    ),
    YorksV1ProjectSetupCompletionText.summaryTitle: TranslatableString(
      en: 'Project summary',
      ar: 'ملخص المشروع',
      ur: 'پراجیکٹ کا خلاصہ',
      hi: 'प्रोजेक्ट सारांश',
    ),
    YorksV1ProjectSetupCompletionText.summaryDescription: TranslatableString(
      en: 'Key details for this project.',
      ar: 'التفاصيل الرئيسية لهذا المشروع.',
      ur: 'اس پراجیکٹ کی اہم تفصیلات۔',
      hi: 'इस प्रोजेक्ट की मुख्य जानकारी।',
    ),
    YorksV1ProjectSetupCompletionText.nextActionsTitle: TranslatableString(
      en: 'Next actions',
      ar: 'الإجراءات التالية',
      ur: 'اگلے اقدامات',
      hi: 'अगली कार्रवाइयाँ',
    ),
    YorksV1ProjectSetupCompletionText.nextActionsDescription:
        TranslatableString(
          en: 'Get started with your project.',
          ar: 'ابدأ العمل على مشروعك.',
          ur: 'اپنے پراجیکٹ پر کام شروع کریں۔',
          hi: 'अपने प्रोजेक्ट पर काम शुरू करें।',
        ),
    YorksV1ProjectSetupCompletionText.nextStepsTitle: TranslatableString(
      en: 'What you can do now',
      ar: 'ما يمكنك فعله الآن',
      ur: 'اب آپ کیا کر سکتے ہیں',
      hi: 'अब आप क्या कर सकते हैं',
    ),
    YorksV1ProjectSetupCompletionText.nextStepsDescription: TranslatableString(
      en: 'Here are the next steps available for this project.',
      ar: 'هذه هي الخطوات التالية المتاحة لهذا المشروع.',
      ur: 'اس پراجیکٹ کے لیے دستیاب اگلے مراحل یہ ہیں۔',
      hi: 'इस प्रोजेक्ट के लिए उपलब्ध अगले चरण यहाँ दिए गए हैं।',
    ),
    YorksV1ProjectSetupCompletionText.editProject: TranslatableString(
      en: 'Edit project',
      ar: 'تعديل المشروع',
      ur: 'پراجیکٹ میں تبدیلی',
      hi: 'प्रोजेक्ट संपादित करें',
    ),
    YorksV1ProjectSetupCompletionText.openProject: TranslatableString(
      en: 'Open project',
      ar: 'فتح المشروع',
      ur: 'پراجیکٹ کھولیں',
      hi: 'प्रोजेक्ट खोलें',
    ),
    YorksV1ProjectSetupCompletionText.addBoq: TranslatableString(
      en: 'Add BOQ',
      ar: 'إضافة جدول الكميات',
      ur: 'BOQ شامل کریں',
      hi: 'BOQ जोड़ें',
    ),
    YorksV1ProjectSetupCompletionText.inviteTeam: TranslatableString(
      en: 'Invite team',
      ar: 'دعوة الفريق',
      ur: 'ٹیم کو دعوت دیں',
      hi: 'टीम को आमंत्रित करें',
    ),
    YorksV1ProjectSetupCompletionText.uploadDocuments: TranslatableString(
      en: 'Upload documents',
      ar: 'رفع المستندات',
      ur: 'دستاویزات اپ لوڈ کریں',
      hi: 'दस्तावेज़ अपलोड करें',
    ),
    YorksV1ProjectSetupCompletionText.returnToProjects: TranslatableString(
      en: 'Return to projects',
      ar: 'العودة إلى المشاريع',
      ur: 'پراجیکٹس پر واپس جائیں',
      hi: 'प्रोजेक्ट पर वापस जाएँ',
    ),
    YorksV1ProjectSetupCompletionText.editLaterHint: TranslatableString(
      en: 'You can edit supported project details, buildings and parties from within the project when permitted.',
      ar: 'يمكنك تعديل تفاصيل المشروع والمباني والأطراف المدعومة من داخل المشروع عند توفر الصلاحية.',
      ur: 'اجازت ملنے پر آپ پراجیکٹ کے اندر سے دستیاب تفصیلات، عمارتوں اور متعلقہ فریقوں میں تبدیلی کر سکتے ہیں۔',
      hi: 'अनुमति होने पर आप प्रोजेक्ट के भीतर समर्थित विवरण, भवन और पक्ष संपादित कर सकते हैं।',
    ),
    YorksV1ProjectSetupCompletionText.referenceLabel: TranslatableString(
      en: 'Project reference',
      ar: 'مرجع المشروع',
      ur: 'پراجیکٹ ریفرنس',
      hi: 'प्रोजेक्ट संदर्भ',
    ),
    YorksV1ProjectSetupCompletionText.nameLabel: TranslatableString(
      en: 'Project name',
      ar: 'اسم المشروع',
      ur: 'پراجیکٹ کا نام',
      hi: 'प्रोजेक्ट का नाम',
    ),
    YorksV1ProjectSetupCompletionText.activeState: TranslatableString(
      en: 'Active',
      ar: 'نشط',
      ur: 'فعال',
      hi: 'सक्रिय',
    ),
    YorksV1ProjectSetupCompletionText.draftState: TranslatableString(
      en: 'Draft',
      ar: 'مسودة',
      ur: 'ڈرافٹ',
      hi: 'ड्राफ़्ट',
    ),
    YorksV1ProjectSetupCompletionText.onHoldState: TranslatableString(
      en: 'On hold',
      ar: 'معلق',
      ur: 'عارضی طور پر روکا گیا',
      hi: 'स्थगित',
    ),
    YorksV1ProjectSetupCompletionText.completedState: TranslatableString(
      en: 'Completed',
      ar: 'مكتمل',
      ur: 'مکمل',
      hi: 'पूर्ण',
    ),
    YorksV1ProjectSetupCompletionText.archivedState: TranslatableString(
      en: 'Archived',
      ar: 'مؤرشف',
      ur: 'آرکائیو شدہ',
      hi: 'संग्रहित',
    ),
    YorksV1ProjectSetupCompletionText.dismissBanner: TranslatableString(
      en: 'Dismiss success message',
      ar: 'إخفاء رسالة النجاح',
      ur: 'کامیابی کا پیغام بند کریں',
      hi: 'सफलता संदेश हटाएँ',
    ),
    YorksV1ProjectSetupCompletionText.addBoqStepTitle: TranslatableString(
      en: 'Add a BOQ',
      ar: 'أضف جدول كميات',
      ur: 'بی او کیو شامل کریں',
      hi: 'बीओक्यू जोड़ें',
    ),
    YorksV1ProjectSetupCompletionText.addBoqDescription: TranslatableString(
      en: 'Create or import your Bill of Quantities to start planning materials.',
      ar: 'أنشئ جدول الكميات أو استورده لبدء تخطيط المواد.',
      ur: 'مواد کی منصوبہ بندی شروع کرنے کے لیے مقداروں کا بل بنائیں یا امپورٹ کریں۔',
      hi: 'सामग्री की योजना शुरू करने के लिए अपनी मात्रा सूची बनाएँ या आयात करें।',
    ),
    YorksV1ProjectSetupCompletionText.createRequests: TranslatableString(
      en: 'Create material requests',
      ar: 'إنشاء طلبات المواد',
      ur: 'مواد کی درخواستیں بنائیں',
      hi: 'सामग्री अनुरोध बनाएँ',
    ),
    YorksV1ProjectSetupCompletionText.createRequestsDescription:
        TranslatableString(
          en: 'Raise material requests for approval and tracking.',
          ar: 'قدّم طلبات المواد للموافقة والمتابعة.',
          ur: 'منظوری اور ٹریکنگ کے لیے مواد کی درخواستیں دیں۔',
          hi: 'स्वीकृति और निगरानी के लिए सामग्री अनुरोध भेजें।',
        ),
    YorksV1ProjectSetupCompletionText.uploadDocumentsStepTitle:
        TranslatableString(
          en: 'Upload project documents',
          ar: 'ارفع مستندات المشروع',
          ur: 'پراجیکٹ دستاویزات اپ لوڈ کریں',
          hi: 'प्रोजेक्ट दस्तावेज़ अपलोड करें',
        ),
    YorksV1ProjectSetupCompletionText
        .uploadDocumentsDescription: TranslatableString(
      en: 'Add drawings, specifications and other permitted project documents.',
      ar: 'أضف الرسومات والمواصفات ومستندات المشروع الأخرى المسموح بها.',
      ur: 'ڈرائنگز، تفصیلات اور پراجیکٹ کی دیگر مجاز دستاویزات شامل کریں۔',
      hi: 'ड्रॉइंग, विनिर्देश और अन्य अनुमत प्रोजेक्ट दस्तावेज़ जोड़ें।',
    ),
    YorksV1ProjectSetupCompletionText.inviteTeamStepTitle: TranslatableString(
      en: 'Invite your team',
      ar: 'ادعُ فريقك',
      ur: 'اپنی ٹیم کو مدعو کریں',
      hi: 'अपनी टीम को आमंत्रित करें',
    ),
    YorksV1ProjectSetupCompletionText.inviteTeamDescription: TranslatableString(
      en: 'Give authorized colleagues access to collaborate on this project.',
      ar: 'امنح الزملاء المخولين صلاحية الوصول للتعاون في هذا المشروع.',
      ur: 'مجاز ساتھیوں کو اس پراجیکٹ پر تعاون کے لیے رسائی دیں۔',
      hi: 'अधिकृत सहकर्मियों को इस प्रोजेक्ट पर सहयोग के लिए पहुँच दें।',
    ),
  };
}
