+++
title = "Support for thread dump in hprof-slurp 0.5.0"
description = "The 0.5.0 release of hprof-slurp supports thread dump"
date = 2022-10-17
[taxonomies]
tags=["hprof-slurp", "release"]
+++

This short article is an announcement for the [0.5.0](https://github.com/agourlay/hprof-slurp/releases/tag/v0.5.0) release of the [hprof-slurp](https://github.com/agourlay/hprof-slurp) project.

The goal of this project is to build a JVM heap dump analyzer written in Rust specialized for very large heap dumps.

This release introduces the support for reporting the traces of the threads found in the heap dump.

Meaning, users can now see which part of their application was running at the time of the dump!

It is achieved by stitching together the stacktrace and stackframe data into a coherent output at the end of the parsing phase.

It may slightly increase the memory consumption at runtime due to the additional data captured.

There is still room for improvement as important pieces of information are missing, such as the name of the thread and its [Java Thread.State](https://docs.oracle.com/en/java/javase/18/docs/api/java.base/java/lang/Thread.State.html).

However, the addition of this feature is a net improvement over what was previously possible and will hopefully help users during their investigations.

All non-empty threads's stacktraces are reported and their format should be compatible with existing tools, such as the `Analyze stacktrace` feature in Intellij IDEA for convenience.

## Example

I will use the `pets.bin` dump file introduced in a previous benchmarking [article](https://agourlay.github.io/rust-performance-retrospective-part1/).

This is a 34Gb heap dump taken while hammering a running instance of [Spring's REST petclinic](https://github.com/spring-petclinic/spring-petclinic-rest).

The thread dump feature is on by default, the analysis of `pets.bin` outputs a total of 224 stacktraces.

Below is the longest I could find for fun.

```txt
Thread 222
  at jdk.internal.misc.Unsafe.park (Unsafe.java:native method)
  at java.util.concurrent.locks.LockSupport.parkNanos (LockSupport.java:252)
  at java.util.concurrent.SynchronousQueue$TransferQueue.transfer (SynchronousQueue.java:704)
  at java.util.concurrent.SynchronousQueue.poll (SynchronousQueue.java:903)
  at com.zaxxer.hikari.util.ConcurrentBag.borrow (ConcurrentBag.java:151)
  at com.zaxxer.hikari.pool.HikariPool.getConnection (HikariPool.java:180)
  at com.zaxxer.hikari.pool.HikariPool.getConnection (HikariPool.java:162)
  at com.zaxxer.hikari.HikariDataSource.getConnection (HikariDataSource.java:128)
  at org.hibernate.engine.jdbc.connections.internal.DatasourceConnectionProviderImpl.getConnection (DatasourceConnectionProviderImpl.java:122)
  at org.hibernate.internal.NonContextualJdbcConnectionAccess.obtainConnection (NonContextualJdbcConnectionAccess.java:38)
  at org.hibernate.resource.jdbc.internal.LogicalConnectionManagedImpl.acquireConnectionIfNeeded (LogicalConnectionManagedImpl.java:108)
  at org.hibernate.resource.jdbc.internal.LogicalConnectionManagedImpl.getPhysicalConnection (LogicalConnectionManagedImpl.java:138)
  at org.hibernate.internal.SessionImpl.connection (SessionImpl.java:520)
  at org.springframework.orm.jpa.vendor.HibernateJpaDialect.beginTransaction (HibernateJpaDialect.java:152)
  at org.springframework.orm.jpa.JpaTransactionManager.doBegin (JpaTransactionManager.java:421)
  at org.springframework.transaction.support.AbstractPlatformTransactionManager.startTransaction (AbstractPlatformTransactionManager.java:400)
  at org.springframework.transaction.support.AbstractPlatformTransactionManager.getTransaction (AbstractPlatformTransactionManager.java:373)
  at org.springframework.transaction.interceptor.TransactionAspectSupport.createTransactionIfNecessary (TransactionAspectSupport.java:595)
  at org.springframework.transaction.interceptor.TransactionAspectSupport.invokeWithinTransaction (TransactionAspectSupport.java:382)
  at org.springframework.transaction.interceptor.TransactionInterceptor.invoke (TransactionInterceptor.java:119)
  at org.springframework.aop.framework.ReflectiveMethodInvocation.proceed (ReflectiveMethodInvocation.java:186)
  at org.springframework.aop.framework.CglibAopProxy$CglibMethodInvocation.proceed (CglibAopProxy.java:753)
  at org.springframework.aop.framework.CglibAopProxy$DynamicAdvisedInterceptor.intercept (CglibAopProxy.java:698)
  at org.springframework.samples.petclinic.service.ClinicServiceImpl$$EnhancerBySpringCGLIB$$a06977e9.findAllVisits (<generated>:unknown line number)
  at org.springframework.samples.petclinic.rest.controller.VisitRestController.listVisits (VisitRestController.java:60)
  at org.springframework.samples.petclinic.rest.controller.VisitRestController$$FastClassBySpringCGLIB$$8641bcb0.invoke (<generated>:unknown line number)
  at org.springframework.cglib.proxy.MethodProxy.invoke (MethodProxy.java:218)
  at org.springframework.aop.framework.CglibAopProxy$CglibMethodInvocation.invokeJoinpoint (CglibAopProxy.java:783)
  at org.springframework.aop.framework.ReflectiveMethodInvocation.proceed (ReflectiveMethodInvocation.java:163)
  at org.springframework.aop.framework.CglibAopProxy$CglibMethodInvocation.proceed (CglibAopProxy.java:753)
  at org.springframework.validation.beanvalidation.MethodValidationInterceptor.invoke (MethodValidationInterceptor.java:123)
  at org.springframework.aop.framework.ReflectiveMethodInvocation.proceed (ReflectiveMethodInvocation.java:186)
  at org.springframework.aop.framework.CglibAopProxy$CglibMethodInvocation.proceed (CglibAopProxy.java:753)
  at org.springframework.aop.framework.CglibAopProxy$DynamicAdvisedInterceptor.intercept (CglibAopProxy.java:698)
  at org.springframework.samples.petclinic.rest.controller.VisitRestController$$EnhancerBySpringCGLIB$$2bf2b676.listVisits (<generated>:unknown line number)
  at jdk.internal.reflect.NativeMethodAccessorImpl.invoke0 (NativeMethodAccessorImpl.java:native method)
  at jdk.internal.reflect.NativeMethodAccessorImpl.invoke (NativeMethodAccessorImpl.java:77)
  at jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke (DelegatingMethodAccessorImpl.java:43)
  at java.lang.reflect.Method.invoke (Method.java:568)
  at org.springframework.web.method.support.InvocableHandlerMethod.doInvoke (InvocableHandlerMethod.java:205)
  at org.springframework.web.method.support.InvocableHandlerMethod.invokeForRequest (InvocableHandlerMethod.java:150)
  at org.springframework.web.servlet.mvc.method.annotation.ServletInvocableHandlerMethod.invokeAndHandle (ServletInvocableHandlerMethod.java:117)
  at org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerAdapter.invokeHandlerMethod (RequestMappingHandlerAdapter.java:895)
  at org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerAdapter.handleInternal (RequestMappingHandlerAdapter.java:808)
  at org.springframework.web.servlet.mvc.method.AbstractHandlerMethodAdapter.handle (AbstractHandlerMethodAdapter.java:87)
  at org.springframework.web.servlet.DispatcherServlet.doDispatch (DispatcherServlet.java:1067)
  at org.springframework.web.servlet.DispatcherServlet.doService (DispatcherServlet.java:963)
  at org.springframework.web.servlet.FrameworkServlet.processRequest (FrameworkServlet.java:1006)
  at org.springframework.web.servlet.FrameworkServlet.doGet (FrameworkServlet.java:898)
  at javax.servlet.http.HttpServlet.service (HttpServlet.java:655)
  at org.springframework.web.servlet.FrameworkServlet.service (FrameworkServlet.java:883)
  at javax.servlet.http.HttpServlet.service (HttpServlet.java:764)
  at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter (ApplicationFilterChain.java:227)
  at org.apache.catalina.core.ApplicationFilterChain.doFilter (ApplicationFilterChain.java:162)
  at org.apache.tomcat.websocket.server.WsFilter.doFilter (WsFilter.java:53)
  at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter (ApplicationFilterChain.java:189)
  at org.apache.catalina.core.ApplicationFilterChain.doFilter (ApplicationFilterChain.java:162)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:327)
  at org.springframework.security.web.access.intercept.FilterSecurityInterceptor.invoke (FilterSecurityInterceptor.java:115)
  at org.springframework.security.web.access.intercept.FilterSecurityInterceptor.doFilter (FilterSecurityInterceptor.java:81)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.access.ExceptionTranslationFilter.doFilter (ExceptionTranslationFilter.java:122)
  at org.springframework.security.web.access.ExceptionTranslationFilter.doFilter (ExceptionTranslationFilter.java:116)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.session.SessionManagementFilter.doFilter (SessionManagementFilter.java:126)
  at org.springframework.security.web.session.SessionManagementFilter.doFilter (SessionManagementFilter.java:81)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.authentication.AnonymousAuthenticationFilter.doFilter (AnonymousAuthenticationFilter.java:109)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.servletapi.SecurityContextHolderAwareRequestFilter.doFilter (SecurityContextHolderAwareRequestFilter.java:149)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.savedrequest.RequestCacheAwareFilter.doFilter (RequestCacheAwareFilter.java:63)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.authentication.logout.LogoutFilter.doFilter (LogoutFilter.java:103)
  at org.springframework.security.web.authentication.logout.LogoutFilter.doFilter (LogoutFilter.java:89)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.header.HeaderWriterFilter.doHeadersAfter (HeaderWriterFilter.java:90)
  at org.springframework.security.web.header.HeaderWriterFilter.doFilterInternal (HeaderWriterFilter.java:75)
  at org.springframework.web.filter.OncePerRequestFilter.doFilter (OncePerRequestFilter.java:117)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.context.SecurityContextPersistenceFilter.doFilter (SecurityContextPersistenceFilter.java:110)
  at org.springframework.security.web.context.SecurityContextPersistenceFilter.doFilter (SecurityContextPersistenceFilter.java:80)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.context.request.async.WebAsyncManagerIntegrationFilter.doFilterInternal (WebAsyncManagerIntegrationFilter.java:55)
  at org.springframework.web.filter.OncePerRequestFilter.doFilter (OncePerRequestFilter.java:117)
  at org.springframework.security.web.FilterChainProxy$VirtualFilterChain.doFilter (FilterChainProxy.java:336)
  at org.springframework.security.web.FilterChainProxy.doFilterInternal (FilterChainProxy.java:211)
  at org.springframework.security.web.FilterChainProxy.doFilter (FilterChainProxy.java:183)
  at org.springframework.web.filter.DelegatingFilterProxy.invokeDelegate (DelegatingFilterProxy.java:354)
  at org.springframework.web.filter.DelegatingFilterProxy.doFilter (DelegatingFilterProxy.java:267)
  at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter (ApplicationFilterChain.java:189)
  at org.apache.catalina.core.ApplicationFilterChain.doFilter (ApplicationFilterChain.java:162)
  at org.springframework.web.filter.RequestContextFilter.doFilterInternal (RequestContextFilter.java:100)
  at org.springframework.web.filter.OncePerRequestFilter.doFilter (OncePerRequestFilter.java:117)
  at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter (ApplicationFilterChain.java:189)
  at org.apache.catalina.core.ApplicationFilterChain.doFilter (ApplicationFilterChain.java:162)
  at org.springframework.web.filter.FormContentFilter.doFilterInternal (FormContentFilter.java:93)
  at org.springframework.web.filter.OncePerRequestFilter.doFilter (OncePerRequestFilter.java:117)
  at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter (ApplicationFilterChain.java:189)
  at org.apache.catalina.core.ApplicationFilterChain.doFilter (ApplicationFilterChain.java:162)
  at org.springframework.boot.actuate.metrics.web.servlet.WebMvcMetricsFilter.doFilterInternal (WebMvcMetricsFilter.java:96)
  at org.springframework.web.filter.OncePerRequestFilter.doFilter (OncePerRequestFilter.java:117)
  at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter (ApplicationFilterChain.java:189)
  at org.apache.catalina.core.ApplicationFilterChain.doFilter (ApplicationFilterChain.java:162)
  at org.springframework.web.filter.CharacterEncodingFilter.doFilterInternal (CharacterEncodingFilter.java:201)
  at org.springframework.web.filter.OncePerRequestFilter.doFilter (OncePerRequestFilter.java:117)
  at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter (ApplicationFilterChain.java:189)
  at org.apache.catalina.core.ApplicationFilterChain.doFilter (ApplicationFilterChain.java:162)
  at org.apache.catalina.core.StandardWrapperValve.invoke (StandardWrapperValve.java:197)
  at org.apache.catalina.core.StandardContextValve.invoke (StandardContextValve.java:97)
  at org.apache.catalina.authenticator.AuthenticatorBase.invoke (AuthenticatorBase.java:540)
  at org.apache.catalina.core.StandardHostValve.invoke (StandardHostValve.java:135)
  at org.apache.catalina.valves.ErrorReportValve.invoke (ErrorReportValve.java:92)
  at org.apache.catalina.core.StandardEngineValve.invoke (StandardEngineValve.java:78)
  at org.apache.catalina.connector.CoyoteAdapter.service (CoyoteAdapter.java:357)
  at org.apache.coyote.http11.Http11Processor.service (Http11Processor.java:382)
  at org.apache.coyote.AbstractProcessorLight.process (AbstractProcessorLight.java:65)
  at org.apache.coyote.AbstractProtocol$ConnectionHandler.process (AbstractProtocol.java:895)
  at org.apache.tomcat.util.net.NioEndpoint$SocketProcessor.doRun (NioEndpoint.java:1732)
  at org.apache.tomcat.util.net.SocketProcessorBase.run (SocketProcessorBase.java:49)
  at org.apache.tomcat.util.threads.ThreadPoolExecutor.runWorker (ThreadPoolExecutor.java:1191)
  at org.apache.tomcat.util.threads.ThreadPoolExecutor$Worker.run (ThreadPoolExecutor.java:659)
  at org.apache.tomcat.util.threads.TaskThread$WrappingRunnable.run (TaskThread.java:61)
  at java.lang.Thread.run (Thread.java:833)
```
