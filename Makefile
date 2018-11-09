local: index.bs
	bikeshed --die-on=warning spec index.bs index.html

remote: index.bs
	curl --fail https://api.csswg.org/bikeshed/ -f -F file=@index.bs > index.html

ci: index.bs
	curl --fail https://api.csswg.org/bikeshed/ -f -F file=@index.bs -F output=err -F die-on=warning
	curl --fail https://api.csswg.org/bikeshed/ -f -F file=@index.bs > out/index.html
