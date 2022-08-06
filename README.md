### What is this?
* A demo of deploying a complex application with Terraform Cloud in an automated CICD pipeline and AWS Systems Manager (for advanced bootstrapping).
  * I've picked [Open edX](https://openedx.org/) for this purpose, since it's a free and open-source learning management system (LMS)

### Why did you build this?
* I wanted to demo how you can host specific applications and platforms on AWS in an automated way using Terraform Cloud and AWS Systems Manager
* Open edX was picked since it has a pretty slick installation utility, and LMS tend to have a lot of moving parts involved
  * Since there are a lot of components within an LMS such as Open edX, this provides a great example of an app that cannot be installed gracefully using only EC2 instance userdata

### Notes
* This is NOT a full installation and configuration of Open edX. Open edX requires much more setup, configuration, and hardening
  * The point of Open edX is to only showcase Terraform Cloud and AWS Systems Manager, specifically State Manager and Run Command
  * However, this _could_ be adapted into more production-ready code. The MIT license is very permissive.
  * You can also hire my services for a more thorough, personalized build. [Check out my freelancing site](https://www.redbellsoftware.com/)


### Workaround for issue with Pycharm and interpreting Terraform modules (could not locate module, unknown error)
* https://github.com/VladRassokhin/intellij-hcl/issues/365#issuecomment-996780121

### Helpful link to Tutor (Open edX deploy/manage utility)
* https://docs.tutor.overhang.io/local.html