using System.Collections.Generic;
using System.ComponentModel;
using System.Resources;
using System.Windows.Forms;

namespace WireSockUI.Extensions
{
    [ProvideProperty("ResourceKey", typeof(Control))]
    public class ControlTextExtender : Component, IExtenderProvider, ISupportInitialize
    {
        private readonly Dictionary<Control, string> _items;

        public ControlTextExtender()
        {
            _items = new Dictionary<Control, string>();
        }

        [Description("Full name of resource class, like YourAppNamespace.Resource1")]
        public string ResourceClassName { get; set; }

        public bool CanExtend(object extendee)
        {
            return extendee is Control;
        }

        public void BeginInit()
        {
        }

        public void EndInit()
        {
            if (DesignMode)
                return;

            var resourceManage = new ResourceManager(ResourceClassName, GetType().Assembly);

            foreach (var menuItem in _items)
            {
                var value = resourceManage.GetString(menuItem.Value);
                menuItem.Key.Text = value;
            }
        }

        public string GetResourceKey(Control item)
        {
            if (_items.TryGetValue(item, out var value))
                return value;

            return null;
        }

        public void SetResourceKey(Control item, string key)
        {
            if (string.IsNullOrEmpty(key))
                _items.Remove(item);
            else
                _items[item] = key;
        }
    }
}