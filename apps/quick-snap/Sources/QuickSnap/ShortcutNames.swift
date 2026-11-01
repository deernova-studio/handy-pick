import QuickSnapCore

extension ShortcutBinding {
    var displayName: String {
        switch self {
        case .mouse(2): return "鼠标中键"
        case .mouse(let button): return "鼠标侧键 \(button + 1)"
        case .modifier(let code): return Self.keyName(code)
        case .key(let code, let flags):
            var prefix = ""
            for (mask, symbol) in [(UInt64(1 << 18), "⌃"), (UInt64(1 << 19), "⌥"), (UInt64(1 << 17), "⇧"), (UInt64(1 << 20), "⌘")] {
                if flags & mask != 0 { prefix += symbol }
            }
            return prefix + Self.keyName(code)
        }
    }

    private static func keyName(_ code: UInt16) -> String {
        let names: [UInt16: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
            12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",
            24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",
            36:"Return",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",
            48:"Tab",49:"空格",50:"`",51:"Delete",53:"Esc",54:"右 Command",55:"左 Command",56:"左 Shift",
            57:"Caps Lock",58:"左 Option",59:"左 Control",60:"右 Shift",61:"右 Option",62:"右 Control",63:"Fn",
            64:"F17",65:"小数点",67:"数字键盘 ×",69:"数字键盘 +",71:"Clear",75:"数字键盘 ÷",76:"Enter",
            78:"数字键盘 −",79:"F18",80:"F19",81:"数字键盘 =",82:"数字键盘 0",83:"数字键盘 1",
            84:"数字键盘 2",85:"数字键盘 3",86:"数字键盘 4",87:"数字键盘 5",88:"数字键盘 6",
            89:"数字键盘 7",91:"数字键盘 8",92:"数字键盘 9",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",
            101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",
            114:"Help",115:"Home",116:"Page Up",117:"向前删除",118:"F4",119:"End",120:"F2",
            121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"
        ]
        return names[code] ?? "键位 \(code)"
    }
}
