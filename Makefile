# parameters
.DEFAULT_GOAL := info

info:
	@echo "Make-Opsnotice :"
	@echo "			- dev (launch development server)"
	@echo "			- build (build Docker image)"
	@echo "			- push (push Docker image)"
	@echo
# Launch Dev environment
dev:
	git submodule update --remote
	hugo server --disableFastRender --gc --bind :: -b localhost

build:  
	sudo docker build -t $(IMAGE_NAME) .

push:  
	sudo docker push $(IMAGE_NAME) 

