pragma Singleton
import QtQuick

// Versão vazia para o greeter: o LockView referencia o NotifService (botão
// Não perturbe), mas antes do login não existe mako nem notificação.
QtObject {
    property bool dnd: false
    property int unreadCount: 0
    property int maxId: 0
    function toggleDnd() {}
    function refresh() {}
    function setCleared(id) {}
}
