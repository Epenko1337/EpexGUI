using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace WireSockUI.Native
{
    internal static class CommonControlExtensions
    {
        [DllImport("user32", CharSet = CharSet.Unicode, SetLastError = false)]
        private static extern IntPtr SendMessage(HandleRef hWnd, UInt32 Msg, UInt32 wParam, [In][Out] ref CHARFORMAT2W lParam);

        [DllImport("user32", CharSet = CharSet.Unicode, SetLastError = false)]
        private static extern IntPtr SendMessage(HandleRef hWnd, UInt32 Msg, UInt32 wParam, [MarshalAs(UnmanagedType.LPWStr)] string lParam);

        private const int WM_USER = 0x400;
        private const int EM_GETCHARFORMAT = WM_USER + 58;
        private const int EM_SETCHARFORMAT = WM_USER + 68;

        private const int EM_SETCUEBANNER = 0x1501;

        /* EM_SETCHARFORMAT wparam masks */
        internal const uint SCF_SELECTION = 0x0001;
        internal const uint SCF_WORD = 0x0002;
        internal const uint SCF_DEFAULT = 0x0000;   // set the default charformat or paraformat
        internal const uint SCF_ALL = 0x0004;   // not valid with SCF_SELECTION or SCF_WORD
        internal const uint SCF_USEUIRULES = 0x0008;   // modifier for SCF_SELECTION; says that
                                                      // the format came from a toolbar, etc. and
                                                      // therefore UI formatting rules should be
                                                      // used instead of strictly formatting the
                                                      // selection.

        [StructLayout(LayoutKind.Sequential)]
        private struct CHARFORMAT2W
        {
            public static uint SIZE = (uint)Marshal.SizeOf(typeof(CHARFORMAT2W));

            public uint cbSize;
            public CHARFORMAT_MASKS dwMask;
            public CHARFORMAT_EFFECTS dwEffects;
            public int yHeight;
            public int yOffset;
            public int crTextColor; // 0x00bbggrr
            public byte bCharSet;
            public byte bPitchAndFamily;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
            public byte[] szFaceName;
            public ushort wWeight;
            public short sSpacing;
            public int crBackColor; // 0x00bbggrr
            public uint lcid;
            public uint dwReserved;
            public short sStyle;
            public ushort wKerning;
            public CHARFORMAT_UNDERLINE bUnderlineType;
            public byte bAnimation;
            public byte bRevAuthor;
            public CHARFORMAT_UNDERLINE_COLOR bUnderlineColor; // bReserved1

            public string FaceName
            {
                get { return Encoding.Unicode.GetString(szFaceName); }
                set { szFaceName = Encoding.Unicode.GetBytes(value); }
            }

            public int yHeight_Points
            {
                get { return yHeight / 20; }
                set { yHeight = value * 20; }
            }
        }

        [Flags]
        private enum CHARFORMAT_MASKS : uint
        {
            CFM_BOLD = 0x00000001,
            CFM_ITALIC = 0x00000002,
            CFM_UNDERLINE = 0x00000004,
            CFM_STRIKEOUT = 0x00000008,
            CFM_PROTECTED = 0x00000010,
            CFM_LINK = 0x00000020, // Exchange hyperlink extension 
            CFM_SIZE = 0x80000000,
            CFM_COLOR = 0x40000000,
            CFM_FACE = 0x20000000,
            CFM_OFFSET = 0x10000000,
            CFM_CHARSET = 0x08000000,

            CFM_SMALLCAPS = 0x0040,
            CFM_ALLCAPS = 0x0080,
            CFM_HIDDEN = 0x0100,
            CFM_OUTLINE = 0x0200,
            CFM_SHADOW = 0x0400,
            CFM_EMBOSS = 0x0800,
            CFM_IMPRINT = 0x1000,
            CFM_DISABLED = 0x2000,
            CFM_REVISED = 0x4000,

            CFM_BACKCOLOR = 0x04000000,
            CFM_LCID = 0x02000000,
            CFM_UNDERLINETYPE = 0x00800000,
            CFM_WEIGHT = 0x00400000,
            CFM_SPACING = 0x00200000,
            CFM_KERNING = 0x00100000,
            CFM_STYLE = 0x00080000,
            CFM_ANIMATION = 0x00040000,
            CFM_REVAUTHOR = 0x00008000,

            CFM_SUBSCRIPT = (CHARFORMAT_EFFECTS.CFE_SUBSCRIPT | CHARFORMAT_EFFECTS.CFE_SUPERSCRIPT),
            CFM_SUPERSCRIPT = CFM_SUBSCRIPT,

            //CFM_EFFECTS = (CFM_BOLD | CFM_ITALIC | CFM_UNDERLINE | CFM_COLOR | CFM_STRIKEOUT | CHARFORMAT_EFFECTS.CFE_PROTECTED | CFM_LINK),
            //CFM_ALL = (CFM_EFFECTS | CFM_SIZE | CFM_FACE | CFM_OFFSET | CFM_CHARSET),
            //CFM_EFFECTS2 = (CFM_EFFECTS | CFM_DISABLED | CFM_SMALLCAPS | CFM_ALLCAPS | CFM_HIDDEN | CFM_OUTLINE | CFM_SHADOW | CFM_EMBOSS | CFM_IMPRINT | CFM_DISABLED | CFM_REVISED | CFM_SUBSCRIPT | CFM_SUPERSCRIPT | CFM_BACKCOLOR),
            //CFM_ALL2 = (CFM_ALL | CFM_EFFECTS2 | CFM_BACKCOLOR | CFM_LCID | CFM_UNDERLINETYPE | CFM_WEIGHT | CFM_REVAUTHOR | CFM_SPACING | CFM_KERNING | CFM_STYLE | CFM_ANIMATION),
        }

        [Flags]
        private enum CHARFORMAT_EFFECTS : uint
        {
            CFE_BOLD = 0x0001,
            CFE_ITALIC = 0x0002,
            CFE_UNDERLINE = 0x0004,
            CFE_STRIKEOUT = 0x0008,
            CFE_PROTECTED = 0x0010,
            CFE_LINK = 0x0020,
            CFE_AUTOCOLOR = 0x40000000, // NOTE: this corresponds to CFM_COLOR, which controls it

            CFE_SUBSCRIPT = 0x00010000, // Superscript and subscript are mutually exclusive
            CFE_SUPERSCRIPT = 0x00020000,

            CFE_SMALLCAPS = CHARFORMAT_MASKS.CFM_SMALLCAPS,
            CFE_ALLCAPS = CHARFORMAT_MASKS.CFM_ALLCAPS,
            CFE_HIDDEN = CHARFORMAT_MASKS.CFM_HIDDEN,
            CFE_OUTLINE = CHARFORMAT_MASKS.CFM_OUTLINE,
            CFE_SHADOW = CHARFORMAT_MASKS.CFM_SHADOW,
            CFE_EMBOSS = CHARFORMAT_MASKS.CFM_EMBOSS,
            CFE_IMPRINT = CHARFORMAT_MASKS.CFM_IMPRINT,
            CFE_DISABLED = CHARFORMAT_MASKS.CFM_DISABLED,
            CFE_REVISED = CHARFORMAT_MASKS.CFM_REVISED,

            CFE_AUTOBACKCOLOR = CHARFORMAT_MASKS.CFM_BACKCOLOR, // CFE_AUTOCOLOR and CFE_AUTOBACKCOLOR correspond to CFM_COLOR and // CFM_BACKCOLOR, respectively, which control them
        }

        private enum CHARFORMAT_UNDERLINE : byte
        {
            CFU_CF1UNDERLINE = 0xFF, // Map charformat's bit underline to CF2
            CFU_INVERT = 0xFE, // For IME composition fake a selection

            CFU_UNDERLINETHICKLONGDASH = 18,
            CFU_UNDERLINETHICKDOTTED = 17,
            CFU_UNDERLINETHICKDASHDOTDOT = 16,
            CFU_UNDERLINETHICKDASHDOT = 15,
            CFU_UNDERLINETHICKDASH = 14,
            CFU_UNDERLINELONGDASH = 13,
            CFU_UNDERLINEHEAVYWAVE = 12,
            CFU_UNDERLINEDOUBLEWAVE = 11,
            CFU_UNDERLINEHAIRLINE = 10,
            CFU_UNDERLINETHICK = 9,
            CFU_UNDERLINEWAVE = 8,
            CFU_UNDERLINEDASHDOTDOT = 7,
            CFU_UNDERLINEDASHDOT = 6,
            CFU_UNDERLINEDASH = 5,
            CFU_UNDERLINEDOTTED = 4,
            CFU_UNDERLINEDOUBLE = 3,
            CFU_UNDERLINEWORD = 2,
            CFU_UNDERLINE = 1,
            CFU_UNDERLINENONE = 0,
        }

        private enum CHARFORMAT_UNDERLINE_COLOR : byte
        {
            FontColor = 0,
            Black = 1,
            Blue = 2,
            Aqua = 3,
            Lime = 4,
            Fuchsia = 5,
            Red = 6,
            Yellow = 7,
            White = 8,
            Navy = 9,
            Teal = 10,
            Green = 11,
            Purple = 12,
            Maroon = 13,
            Olive = 14,
            DarkkGray = 15,
            LightGray = 16
        }

        private static CHARFORMAT2W GetCharFormat(RichTextBox richTextBox, bool fSelection)
        {
            CHARFORMAT2W format = new CHARFORMAT2W();
            format.cbSize = CHARFORMAT2W.SIZE;
            SendMessage(new HandleRef(richTextBox, richTextBox.Handle), EM_GETCHARFORMAT, fSelection ? SCF_SELECTION : SCF_ALL, ref format);
            return format;
        }

        private static void SetCharFormat(RichTextBox richTextBox, bool fSelection, CHARFORMAT2W format)
        {
            format.cbSize = CHARFORMAT2W.SIZE;
            SendMessage(new HandleRef(richTextBox, richTextBox.Handle), EM_SETCHARFORMAT, (fSelection ? SCF_SELECTION : SCF_ALL), ref format);
        }

        private static CHARFORMAT2W GetSelectionCharFormat(RichTextBox richTextBox)
        {
            return GetCharFormat(richTextBox, true);
        }

        /// <summary>
        /// Apply red wavy underline to a current selection in a <see cref="RichTextBox"/>
        /// </summary>
        /// <param name="richTextBox"><see cref="RichTextBox"/></param>
        public static void UnderlineSelection(this RichTextBox richTextBox)
        {
            CHARFORMAT2W format = new CHARFORMAT2W()
            {
                dwMask = CHARFORMAT_MASKS.CFM_UNDERLINE | CHARFORMAT_MASKS.CFM_UNDERLINETYPE,
                dwEffects = CHARFORMAT_EFFECTS.CFE_UNDERLINE,
                bUnderlineType = CHARFORMAT_UNDERLINE.CFU_UNDERLINEWAVE,
                bUnderlineColor = CHARFORMAT_UNDERLINE_COLOR.Red
            };

            SetCharFormat(richTextBox, true, format);
        }

        /// <summary>
        /// Set a user cue to action message for a <see cref="TextBox"/>
        /// </summary>
        /// <param name="textBox"><see cref="TextBox"/></param>
        /// <param name="bannerText">Message to display</param>
        public static void SetCueBanner(this TextBox textBox, string bannerText)
        {
            SendMessage(new HandleRef(textBox, textBox.Handle), EM_SETCUEBANNER, 0, bannerText);
        }
    }
}
