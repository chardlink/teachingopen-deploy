FROM eclipse-temurin:8-jre

WORKDIR /opt/teaching

COPY assets/teaching-open-2.8.0.jar /opt/teaching/app/teaching-open-2.8.0.jar
COPY config/application-prod.yml /opt/teaching/config/application-prod.yml

ENV TZ=Asia/Shanghai
ENV JAVA_OPTS="-Xms512m -Xmx2048m -Dfile.encoding=UTF-8"

CMD ["sh", "-c", "java ${JAVA_OPTS} -jar /opt/teaching/app/teaching-open-2.8.0.jar --spring.profiles.active=prod --spring.config.additional-location=file:/opt/teaching/config/"]
