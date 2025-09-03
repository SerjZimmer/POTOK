import 'dart:convert';
import 'package:flutter/material.dart';
import 'issue_card_helpers.dart';

class SuggestField extends StatelessWidget{
  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  const SuggestField({required this.controller, required this.label, required this.suggestions, super.key});
  @override
  Widget build(BuildContext context){
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      TextField(controller: controller, decoration: InputDecoration(labelText: label)),
      if(suggestions.isNotEmpty)
        SizedBox(
          height: 32,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for(final s in suggestions)
              Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text(s), onPressed: (){ controller.text = s; })),
          ]),
        ),
    ]);
  }
}

class FieldEditor extends StatelessWidget{
  final Map<String,dynamic> field; final dynamic value; final ValueChanged<dynamic> onChanged;
  const FieldEditor({required this.field, required this.value, required this.onChanged, super.key});
  @override
  Widget build(BuildContext context){
    final type = (field['type']??'text') as String;
    final name = (field['name']??'') as String;
    switch(type){
      case 'number':
        return TextField(controller: TextEditingController(text: value?.toString() ?? ''), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: name), onChanged: (v)=> onChanged(num.tryParse(v)));
      case 'date':
        return DateField(label: name, value: value, onChanged: onChanged);
      case 'enum':
        final opts = _parseOptions(field['options']);
        return DropdownButtonFormField<String>(value: (value?.toString().isEmpty ?? true) ? null : value.toString(), items: [for(final o in opts) DropdownMenuItem(value:o, child: Text(o))], onChanged: (v)=> onChanged(v), decoration: InputDecoration(labelText: name));
      case 'user':
        // TODO: user suggestions
        return TextField(controller: TextEditingController(text: value?.toString() ?? ''), decoration: InputDecoration(labelText: name), onChanged: (v)=> onChanged(v));
      default:
        return TextField(controller: TextEditingController(text: value?.toString() ?? ''), decoration: InputDecoration(labelText: name), onChanged: (v)=> onChanged(v));
    }
  }
  List<String> _parseOptions(dynamic raw){
    if(raw==null) return const [];
    try { return (raw is String) ? (raw.trim().isEmpty? [] : List<String>.from((jsonDecode(raw) as List).map((e)=> e.toString()))) : List<String>.from((raw as List).map((e)=> e.toString())); } catch(_){ return const []; }
  }
}

class DateField extends StatefulWidget{
  final String label; final dynamic value; final ValueChanged<dynamic> onChanged;
  const DateField({required this.label, this.value, required this.onChanged, super.key});
  @override State<DateField> createState()=> _DateFieldState();
}
class _DateFieldState extends State<DateField>{
  DateTime? _val;
  @override void initState(){ super.initState(); _val = (widget.value is String)? DateTime.tryParse(widget.value): null; }
  @override Widget build(BuildContext context){
    return Row(children:[
      Expanded(child: Text('${widget.label}: ${_val==null? '—' : fmtDate(_val!)}')), 
      TextButton(onPressed: () async { final now=DateTime.now(); final picked = await showDatePicker(context: context, initialDate: _val?? now, firstDate: DateTime(2000), lastDate: DateTime(2100)); if(picked!=null){ setState(()=> _val = DateTime(picked.year, picked.month, picked.day)); widget.onChanged(_val!.toUtc().toIso8601String()); } }, child: const Text('Выбрать')),
      if(_val!=null) TextButton(onPressed: (){ setState(()=> _val=null); widget.onChanged(null); }, child: const Text('Сбросить'))
    ]);
  }
}
