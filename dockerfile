FROM ubuntu:22.04

ENV BASH_ENV=/etc/profile

RUN mkdir -p /usr/local/provisioning
RUN mkdir -p /usr/local/provisioning/replacements

COPY provisioning/* /usr/local/provisioning
COPY provisioning/replacements/* /usr/local/provisioning/replacements

RUN ls -la /usr/local/provisioning

EXPOSE 4567

ENV TZ=Etc/UTC

RUN ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        lua5.2 \
        liblua5.2-dev \
        postgresql \
        libpq-dev \
        postgresql-server-dev-all \
        pmake \
        imagemagick \
        libbsd-dev \
        python3-pip \
        curl \
        lsb-release && \
    pip3 install markdown2 && \
    dpkg-reconfigure -f noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/*

RUN id -u www-data &>/dev/null || useradd -m -d /home/www-data -s /bin/bash www-data && \
    service postgresql start && \
    su postgres -c "createuser --no-superuser --createdb --no-createrole www-data"

RUN curl -L -o liquid_feedback_core-v3.2.2.tar.gz http://www.public-software-group.org/pub/projects/liquid_feedback/backend/v3.2.2/liquid_feedback_core-v3.2.2.tar.gz && \
    tar xvzf liquid_feedback_core-v3.2.2.tar.gz && \
    cd liquid_feedback_core-v3.2.2 && \
    make && \
    mkdir /opt/liquid_feedback_core && \
    cp core.sql lf_update lf_update_issue_order lf_update_suggestion_order /opt/liquid_feedback_core && \
    cd .. && \
    rm -r liquid_feedback_core-v3.2.2 && \
    rm liquid_feedback_core-v3.2.2.tar.gz

RUN curl -L -O http://www.public-software-group.org/pub/projects/moonbridge/v1.0.1/moonbridge-v1.0.1.tar.gz && \
    tar xvzf moonbridge-v1.0.1.tar.gz && \
    cd moonbridge-v1.0.1 && \
    apt-get update && \
    apt-get install -y liblua5.2-dev && \
    pmake MOONBR_LUA_PATH=/opt/moonbridge/?.lua && \
    mkdir /opt/moonbridge && \
    cp moonbridge /opt/moonbridge/ && \
    cp moonbridge_http.lua /opt/moonbridge/ && \
    cd .. && \
    rm -r moonbridge-v1.0.1 && \
    rm moonbridge-v1.0.1.tar.gz

RUN curl -L -O http://www.public-software-group.org/pub/projects/webmcp/v2.1.0/webmcp-v2.1.0.tar.gz && \
    tar xvzf webmcp-v2.1.0.tar.gz && \
    cd webmcp-v2.1.0 && \
    rm Makefile.options && \
    cp /usr/local/provisioning/replacements/Makefile.options.webmcp Makefile.options && \
    make && \
    mkdir /opt/webmcp && \
    cp -RL framework/* /opt/webmcp/ && \
    cd .. && \
    rm -r webmcp-v2.1.0 && \
    rm webmcp-v2.1.0.tar.gz

RUN curl -L -O http://www.public-software-group.org/pub/projects/liquid_feedback/frontend/v3.2.1/liquid_feedback_frontend-v3.2.1.tar.gz && \
    tar xvzf liquid_feedback_frontend-v3.2.1.tar.gz && \
    mv liquid_feedback_frontend-v3.2.1 /opt/liquid_feedback_frontend && \
    chown www-data /opt/liquid_feedback_frontend/tmp && \
    rm liquid_feedback_frontend-v3.2.1.tar.gz

RUN if [ ! -f /opt/liquid_feedback_core/lf_updated ]; then \
        cp /usr/local/provisioning/replacements/lf_updated /opt/liquid_feedback_core/ && \
        chmod +x /opt/liquid_feedback_core/lf_updated; \
    fi

RUN cd /opt/liquid_feedback_frontend/config && \
    cp example.lua myconfig.lua

RUN service postgresql start && \
    su postgres -s /bin/bash -c "cd /opt/liquid_feedback_core && createdb liquid_feedback && psql -v ON_ERROR_STOP=1 -f core.sql liquid_feedback && psql liquid_feedback -c 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"www-data\";'" && \
    su postgres -s /bin/bash -c "psql liquid_feedback -c 'GRANT USAGE, SELECT ON SEQUENCE unit_id_seq TO \"www-data\";'" && \
    su postgres -s /bin/bash -c "psql liquid_feedback -c 'GRANT USAGE, SELECT ON SEQUENCE area_id_seq TO \"www-data\";'" && \
    su postgres -s /bin/bash -c "psql liquid_feedback -c 'GRANT USAGE, SELECT ON SEQUENCE member_id_seq TO \"www-data\";'" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO system_setting (member_ttl) VALUES ('1 year');\"" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO contingent (polling, time_frame, text_entry_limit, initiative_limit) VALUES (false, '1 hour', 20, 6);\"" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO contingent (polling, time_frame, text_entry_limit, initiative_limit) VALUES (false, '1 day', 80, 12);\"" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO contingent (polling, time_frame, text_entry_limit, initiative_limit) VALUES (true, '1 hour', 200, 60);\"" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO contingent (polling, time_frame, text_entry_limit, initiative_limit) VALUES (true, '1 day', 800, 120);\"" && \
    su postgres -s /bin/bash -c "psql liquid_feedback -c 'GRANT USAGE, SELECT ON SEQUENCE policy_id_seq TO \"www-data\";'" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO policy (index, name, min_admission_time, max_admission_time, discussion_time, verification_time, voting_time, issue_quorum_num, issue_quorum_den, initiative_quorum_num, initiative_quorum_den) VALUES (1, 'Default policy', '4 days', '8 days', '15 days', '8 days', '15 days', 10, 100, 10, 100);\"" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO unit (name) VALUES ('Our organization');\"" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO area (unit_id, name) VALUES (1, 'Default area');\"" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO allowed_policy (area_id, policy_id, default_policy) VALUES (1, 1, TRUE);\"" && \
    su www-data -s /bin/bash -c "psql liquid_feedback -c \"INSERT INTO member (login, name, admin, password, activated, last_activity) VALUES ('admin', 'Administrator', TRUE, '$1$/EMPTY/$NEWt7XJg2efKwPm4vectc1', NOW(), NOW());\""

    CMD ["sh", "-c", "service postgresql start && su postgres -s /bin/bash -c \"psql -c 'SELECT 1'\" && /opt/moonbridge/moonbridge /opt/webmcp/bin/mcp.lua /opt/webmcp/ /opt/liquid_feedback_frontend/ main myconfig"]
