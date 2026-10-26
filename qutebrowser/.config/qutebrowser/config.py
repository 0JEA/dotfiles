config.load_autoconfig(False)
c = config

# Back/forward-cache restores skip qutebrowser's injected JS, so hints/search
# fail with "Unknown error while getting elements" after going back.
config.set('qt.args', ['disable-back-forward-cache'])
