import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    final mother = context.watch<AuthProvider>().user?.isMother == true;
    String tr(String en, String urdu) => ur ? urdu : en;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Help & Support', 'مدد اور تعاون'))),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        if (mother) ...[
          ExpansionTile(
            title: Text(
                tr('What should I enter each day?', 'روزانہ کیا درج کرنا ہے؟')),
            children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr(
                      'One mood answer is enough for your daily check-in. Journal writing, voice notes and extra mood details are optional. Sleep needs only bedtime and wake time.',
                      'روزانہ موڈ کے لیے ایک جواب کافی ہے۔ جریدہ، آواز اور موڈ کی مزید تفصیل اختیاری ہیں۔ نیند کے لیے صرف سونے اور جاگنے کے اوقات چنیں۔')))
            ],
          ),
          ExpansionTile(
            title: Text(tr('When are my tests due?', 'جانچ کب کرنی ہے؟')),
            children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr(
                      'The Tests page shows your schedule and unfinished tests. Your project schedule is weekly EPDS and PHQ-9 every 14 days. You do not need to repeat both every day.',
                      'جانچ کے صفحے پر شیڈول اور نامکمل جانچیں دیکھیں۔ ایپ میں EPDS ہفتہ وار اور PHQ-9 ہر ۱۴ دن بعد ہے۔ دونوں روزانہ دہرانا ضروری نہیں۔')))
            ],
          ),
          ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: Text(tr('My tests', 'میری جانچیں')),
              onTap: () => context.push(AppRoutes.tests)),
          ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(tr('Hum-Raaz support', 'ہم راز معاونت')),
              onTap: () => context.push(AppRoutes.chatbot)),
        ],
        ExpansionTile(
          title: Text(tr(
              'Who can see my information?', 'میری معلومات کون دیکھ سکتا ہے؟')),
          children: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr(
                    'Guardian reports contain permitted summaries. Private journals and Hum-Raaz conversations are not included. Messages you send in Guardian chat are visible to the linked participant.',
                    'سرپرست کی رپورٹس میں اجازت شدہ خلاصے ہوتے ہیں۔ نجی جریدہ اور ہم راز کی گفتگو شامل نہیں۔ سرپرست چیٹ میں بھیجا گیا پیغام منسلک فرد کو نظر آتا ہے۔')))
          ],
        ),
        ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr('Privacy settings', 'رازداری کی ترتیبات')),
            onTap: () => context.push(AppRoutes.privacy)),
        ListTile(
            leading: const Icon(Icons.support_agent),
            title: Text(tr('Immediate help', 'فوری مدد')),
            onTap: () => context.push(AppRoutes.crisis)),
      ])),
    );
  }
}
