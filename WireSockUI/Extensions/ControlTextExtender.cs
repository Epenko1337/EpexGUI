using System.Collections.Generic;
using System.ComponentModel;
using System.Resources;
using System.Windows.Forms;

namespace WireSockUI.Extensions
{
    [ProvideProperty("ResourceKey", typeof(Control))]
    public class ControlTextExtender : Component, System.ComponentModel.IExtenderProvider, ISupportInitialize
    {
        private readonly Dictionary<Control, string> _items;

        public ControlTextExtender() : base()
        {
            _items = new Dictionary<Control, string>();
        }

        [Description("Full name of resource class, like YourAppNamespace.Resource1")]
        public string ResourceClassName { get; set; }

        public bool CanExtend(object extendee)
        {
            return (extendee is Control);
        }

        public string GetResourceKey(Control item)
        {
            if (_items.TryGetValue(item, out string value))
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

        public void BeginInit() { }

        public void EndInit()
        {
            if (DesignMode)
                return;

            ResourceManager resourceManage = new ResourceManager(this.ResourceClassName, this.GetType().Assembly);

            foreach (KeyValuePair<Control, string> menuItem in _items)
            {
                string value = resourceManage.GetString(menuItem.Value);
                menuItem.Key.Text = value;
            }
        }

    }
}
