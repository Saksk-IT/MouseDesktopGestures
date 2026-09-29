; Standalone JSON reader/writer. Distributed with the application under GPL-2.0-or-later.
; SPDX-License-Identifier: GPL-2.0-or-later
class Json
{
    static Null := {}
    static Parse(text)
    {
        reader := JsonReader(text)
        value := reader.Value()
        reader.White()
        if reader.Pos <= StrLen(text)
            throw ValueError("JSON 尾部有多余内容（位置 " reader.Pos "）")
        return value
    }
    static Dump(value, depth := 0)
    {
        if depth > 64
            throw ValueError("JSON 嵌套过深")
        if IsObject(value)
        {
            if value == Json.Null
                return "null"
            pieces := []
            if value is Map
            {
                for key, item in value
                    pieces.Push(Json.Quote(String(key)) ": " Json.Dump(item, depth + 1))
                open := "{", close := "}"
            }
            else if value is Array
            {
                for item in value
                    pieces.Push(Json.Dump(item, depth + 1))
                open := "[", close := "]"
            }
            else
                throw TypeError("不支持的 JSON 对象")
            if !pieces.Length
                return open close
            pad := "", childPad := ""
            Loop depth
                pad .= "  "
            childPad := pad "  "
            result := open "`n"
            for index, piece in pieces
                result .= childPad piece (index < pieces.Length ? "," : "") "`n"
            return result pad close
        }
        if Type(value) = "String"
            return Json.Quote(value)
        if IsNumber(value)
            return String(value)
        throw TypeError("不支持的 JSON 值")
    }
    static Quote(value)
    {
        q := Chr(34), result := q
        Loop Parse value
        {
            ch := A_LoopField
            switch ch
            {
                case Chr(34): result .= "\" q
                case "\": result .= "\\"
                case "`n": result .= "\n"
                case "`r": result .= "\r"
                case "`t": result .= "\t"
                default: result .= Ord(ch) < 32 ? Format("\u{:04X}", Ord(ch)) : ch
            }
        }
        return result q
    }
}

class JsonReader
{
    __New(text)
    {
        this.Text := text
        this.Pos := 1
        this.Depth := 0
    }
    White()
    {
        while this.Pos <= StrLen(this.Text) && InStr(" `t`r`n", SubStr(this.Text, this.Pos, 1))
            this.Pos++
    }
    Fail(message)
    {
        throw ValueError(message "（JSON 位置 " this.Pos "）")
    }
    Value()
    {
        this.White()
        if ++this.Depth > 64
            this.Fail("嵌套过深")
        try
        {
            ch := SubStr(this.Text, this.Pos, 1)
            if ch = Chr(34)
                return this.StringValue()
            if ch = "{" || ch = "["
                return this.Container(ch)
            for literal, value in Map("true", 1, "false", 0, "null", Json.Null)
            {
                if SubStr(this.Text, this.Pos, StrLen(literal)) == literal
                {
                    this.Pos += StrLen(literal)
                    return value
                }
            }
            if RegExMatch(SubStr(this.Text, this.Pos), "^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?", &match)
            {
                this.Pos += StrLen(match[0])
                return InStr(match[0], ".") || InStr(StrLower(match[0]), "e") ? Float(match[0]) : Integer(match[0])
            }
            this.Fail("无法识别的值")
        }
        finally
            this.Depth--
    }
    Container(open)
    {
        object := open = "{"
        result := object ? Map() : []
        close := object ? "}" : "]"
        this.Pos++
        this.White()
        if SubStr(this.Text, this.Pos, 1) = close
        {
            this.Pos++
            return result
        }
        Loop
        {
            this.White()
            if object
            {
                if SubStr(this.Text, this.Pos, 1) != Chr(34)
                    this.Fail("对象键必须是字符串")
                key := this.StringValue()
                if result.Has(key)
                    this.Fail("重复的对象键")
                this.White()
                if SubStr(this.Text, this.Pos++, 1) != ":"
                    this.Fail("缺少冒号")
                result[key] := this.Value()
            }
            else
                result.Push(this.Value())
            this.White()
            ch := SubStr(this.Text, this.Pos++, 1)
            if ch = close
                return result
            if ch != ","
                this.Fail("缺少逗号或结束符")
        }
    }
    StringValue()
    {
        this.Pos++
        value := ""
        while this.Pos <= StrLen(this.Text)
        {
            ch := SubStr(this.Text, this.Pos++, 1)
            if ch = Chr(34)
                return value
            if Ord(ch) < 32
                this.Fail("字符串含未转义的控制字符")
            if ch != "\"
            {
                value .= ch
                continue
            }
            escaped := SubStr(this.Text, this.Pos++, 1)
            switch escaped
            {
                case Chr(34), "\", "/": value .= escaped
                case "n": value .= "`n"
                case "r": value .= "`r"
                case "t": value .= "`t"
                case "b": value .= Chr(8)
                case "f": value .= Chr(12)
                case "u":
                    code := this.HexCode()
                    if code >= 0xD800 && code <= 0xDBFF
                    {
                        if SubStr(this.Text, this.Pos, 2) != "\u"
                            this.Fail("Unicode 高代理项缺少配对")
                        this.Pos += 2
                        low := this.HexCode()
                        if low < 0xDC00 || low > 0xDFFF
                            this.Fail("无效 Unicode 代理对")
                        code := 0x10000 + ((code - 0xD800) << 10) + low - 0xDC00
                    }
                    else if code >= 0xDC00 && code <= 0xDFFF
                        this.Fail("孤立 Unicode 低代理项")
                    if code = 0
                        this.Fail("配置字符串不支持 NUL 字符")
                    value .= Chr(code)
                default: this.Fail("无效字符串转义")
            }
        }
        this.Fail("字符串未结束")
    }
    HexCode()
    {
        hex := SubStr(this.Text, this.Pos, 4)
        if !RegExMatch(hex, "^[0-9A-Fa-f]{4}$")
            this.Fail("无效 Unicode 转义")
        this.Pos += 4
        return Integer("0x" hex)
    }
}
