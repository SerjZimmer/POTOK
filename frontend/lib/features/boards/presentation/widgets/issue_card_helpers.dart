import 'package:flutter/material.dart';
import 'dart:convert';

// Public helper widgets and functions for issue cards and details.

String fmtDate(DateTime d){
  final local = d.toLocal();
  return '${local.year.toString().padLeft(4,'0')}-${local.month.toString().padLeft(2,'0')}-${local.day.toString().padLeft(2,'0')}';
}

class PriorityDef {
  final String key; final String label; final Color color;
  const PriorityDef(this.key, this.label, this.color);
}

class PriorityPalette {
  static final List<PriorityDef> _defs = [
    const PriorityDef('LOW', 'Низкий', Color(0xFF66BB6A)),
    const PriorityDef('MEDIUM', 'Средний', Color(0xFFFFB300)),
    const PriorityDef('HIGH', 'Высокий', Color(0xFFE53935)),
  ];
  static PriorityDef of(String key){
    return _defs.firstWhere((e)=> e.key==key, orElse: ()=> _defs[1]);
  }
}

PriorityDef prioOf(List<Map<String,dynamic>> defs, String key){
  for(final m in defs){ if((m['key']??'') == key){ final hex = (m['colorHex']??'#FFB300') as String; return PriorityDef(key, (m['label']??key) as String, hexToColor(hex)); } }
  return PriorityPalette.of(key);
}

Color hexToColor(String hex){
  var s = hex.replaceFirst('#','');
  if(s.length==6) s = 'FF$s';
  final v = int.tryParse(s, radix:16) ?? 0xFFFFB300;
  return Color(v);
}

class PriorityChip extends StatelessWidget{
  final PriorityDef pr; const PriorityChip({required this.pr, super.key});
  @override Widget build(BuildContext context){
    return Container(
      padding: const EdgeInsets.symmetric(horizontal:8, vertical:2),
      decoration: BoxDecoration(color: pr.color.withOpacity(0.2), borderRadius: BorderRadius.circular(10), border: Border.all(color: pr.color.withOpacity(0.7))),
      child: Row(mainAxisSize: MainAxisSize.min, children:[
        Container(width: 8, height: 8, decoration: BoxDecoration(color: pr.color, shape: BoxShape.circle)),
        const SizedBox(width:6),
        Text(pr.label),
      ]),
    );
  }
}
