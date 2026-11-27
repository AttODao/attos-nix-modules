# What HyperMonitor shows for this kind and the attos-deck-agent may run (modules.service-catalog).
{ ... }:
{
  modules.service-catalog.kinds.mailserver = _: {
    title = "メール";
    kind = "mail";
    units = [
      "postfix.service"
      "dovecot.service"
      "rspamd.service"
    ];
    # SMTP/IMAP only; the hostname's HTTP route belongs to the groupware kind.
    probe = null;
    order = 10;
  };
}
