using System.Collections.Generic;

namespace WireSockUI.Extensions
{
    public static class DictionaryExtensions
    {
        public static TVal Get<TKey, TVal>(this Dictionary<TKey, TVal> dictionary, TKey key, TVal defaultVal = default)
        {
            if (dictionary.TryGetValue(key, out TVal val))
                return val;

            return defaultVal;
        }
    }
}
