(**
 * String structure.
 * @author YAMATODANI Kiyoshi
 * @copyright 2010, Tohoku University.
 * @version $Id: String.sml,v 1.11.12.2 2010/05/09 03:53:48 kiyoshiy Exp $
 *)
(*
 * Because the STRING signature refers to String structure, the STRING
 * signature and the String structure makes a recursive reference.
 * To avoid this, we define the String structure without constraint first,
 * then define the STRING signature, and re-define the String structure
 * constrained by the STRING signature.
 *)
structure String =
struct

  type string = string (* NOTE: string is a primitie type. *)

  type char = char

  (* (SIZE_MASK - 1) * sizeof(UInt32Value) - 1
   * SIZE_MASK is defined in Heap.hh as 0xFFFFFFF.
   * The first '1' means the cell to store string length.
   * The last '1' means a byte for append '\0' character.
   *)
  val maxSize = 0x3FFFFFF7 (* (0xFFFFFFF - 1) * 4 - 1 *)

  val size = SMLSharp.PrimString.size

  fun sub (string, index) =
      if index < 0 orelse size string <= index
      then raise General.Subscript
      else SMLSharp.PrimString.sub_unsafe (string, index)

  fun extract (string, begin, lengthOpt) =
      let
        val stringSize = size string
        val length =
            case lengthOpt of
              NONE => stringSize - begin
            | SOME length => length
      in
        if
          case lengthOpt of
            NONE => (begin < 0) orelse (stringSize < begin)
          | SOME length =>
            (begin < 0)
            orelse (length < 0)
            orelse (stringSize < begin + length)
        then raise General.Subscript
        else
          if (begin = stringSize) andalso (length = 0)
          then ""
          else SMLSharp.Runtime.String_substring (string, begin, length)
      end

  fun substring (string, begin, length) = extract(string, begin, SOME length)

  val String_concat2 = SMLSharp.Runtime.String_concat2

  fun concat [] = ""
    | concat (string :: strings) =
      let
        fun append [] result = result
          | append (head :: tail) result =
            append tail (String_concat2 (result, head))
      in append strings string
      end

  fun concatWith separator [] = ""
    | concatWith separator [string] = string
    | concatWith separator (string :: strings) =
      let
        fun append [] result = result
          | append (head :: tail) result =
            append
                tail
                (String_concat2 (result, String_concat2(separator, head)))
      in append strings string
      end

  val op ^ = op ^ (* ^ is a primitive operator. *)

  fun str ch = SMLSharp.PrimString.vector (1, ch)

  fun implode chars =
      let
        val len = List.length chars
        val buffer = SMLSharp.PrimString.vector (len, #"a")
        fun scan i (c :: cs) =
            (SMLSharp.PrimString.update_unsafe (buffer, i, c); scan (i + 1) cs)
          | scan i [] = ()
      in
        scan 0 chars; buffer
      end

  fun explode string =
      let
        fun accum 0 chars = chars
          | accum n chars = accum (n - 1) (sub (string, n - 1) :: chars)
      in accum (size string) [] end

  fun map mapper string =
      implode(List.map mapper (explode string))

  fun translate translator string =
      concat(List.map translator (explode string))

  fun tokens isDelimiter string =
      let
        val chars = explode string
        fun charsToToken chars = implode (List.rev chars)
        val (chars, tokens) =
            List.foldl
            (fn (char, (chars, tokens)) =>
                if isDelimiter char
                then
                  case chars of
                    [] => ([], tokens)
                  | _ :: _ => ([], charsToToken chars :: tokens)
                else (char :: chars, tokens))
            ([], [])
            chars
        val tokens =
            case chars of
              [] => tokens |
              _ :: _ => (charsToToken chars) :: tokens
      in List.rev tokens end

  fun fields isDelimiter string =
      let
        val chars = explode string
        fun charsToField chars = implode (List.rev chars)
        val (chars, fields) =
            List.foldl
            (fn (char, (chars, fields)) =>
                if isDelimiter char
                then ([], charsToField chars :: fields)
                else (char :: chars, fields))
            ([], [])
            chars
        val fields = (charsToField chars) :: fields
      in List.rev fields end

  local
    fun collateImp
            charCollate
            ((left, leftStart, leftSize), (right, rightStart, rightSize)) =
      let
        fun scan index =
            if leftSize = index orelse rightSize = index
            then
              if leftSize < rightSize
              then General.LESS
              else
                if leftSize = rightSize then General.EQUAL else General.GREATER
            else
              case
                charCollate
                    (
                      sub (left, leftStart + index),
                      sub (right, rightStart + index)
                    )
               of EQUAL => scan (index + 1)
                | notEqual => notEqual
      in scan 0 end
  in

  fun collate charCollate (left, right) =
      let
        val leftSize = size left
        val rightSize = size right
      in
        collateImp charCollate ((left, 0, leftSize), (right, 0, rightSize))
      end

  fun compare x = collate Char.compare x

  fun isPrefix left right =
      let
        val leftSize = size left
        val rightSize = size right
      in
        if rightSize < leftSize
        then false
        else
          General.EQUAL
          = collateImp Char.compare ((left, 0, leftSize), (right, 0, leftSize))
      end

  fun isSubstring left right = 
      let
        val leftSize = size left
        val rightSize = size right
        (* ToDo : rewrite by efficient search algorithm. *)
        fun search index =
            if rightSize - index < leftSize
            then false
            else
              if
                General.EQUAL
                = collateImp
                      Char.compare
                      ((left, 0, leftSize), (right, index, leftSize))
              then true
              else search (index + 1)
      in
        search 0
      end

  fun isSuffix left right =
      let
        val leftSize = size left
        val rightSize = size right
      in
        if rightSize < leftSize
        then false
        else
          General.EQUAL
          = collateImp
                Char.compare
                ((left, 0, leftSize), (right, rightSize - leftSize, leftSize))
      end

  fun op < (left, right) =
      case compare (left, right) of General.LESS => true | _ => false
  fun op <= (left, right) =
      case compare (left, right) of General.GREATER => false | _ => true
  fun op > x = not (op <= x)
  fun op >= x = not (op < x)

  end (* end of local *)

  local structure PC = ParserComb
  in
  (* NONE indicates that the argument starts with an invalid escape sequence
   * or a non-printable (= non-ASCII) character.
   * If the argument is zero-length, SOME("") is returned.
   *)
  fun scan reader stream =
      case PC.wrap(PC.oneOrMore Char.scan, implode) reader stream
       of NONE =>
          if Option.isSome (reader stream)
          then NONE
          else SOME("", stream)
        | x => x

  fun fromString "" = SOME ""
    | fromString string = StringCvt.scanString scan string
  end  
  fun toString string = translate Char.toString string

  local structure PC = ParserComb
  in
  fun fromCString "" = SOME ""
    | fromCString string =
      StringCvt.scanString
          (PC.wrap(PC.oneOrMore Char.scanCString, fn chars => implode chars))
          string
  end  
  fun toCString string = translate Char.toCString string

end