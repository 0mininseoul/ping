using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;

namespace Ping.Windows.App.Setup;

public sealed class PositiveIntToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language) =>
        value is int count && count > 0 ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        value is Visibility.Visible ? 1 : 0;
}
